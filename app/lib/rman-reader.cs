// Lecteur de manifest RMAN (patcher Riot) : en-tête, puis corps FlatBuffers déjà décompressé.
// Compilé par Add-Type depuis lib\riot-text-files.lib.ps1 ; aucune dépendance hors du .NET Framework.
//
// Format (références : CommunityDragon/CDTB cdtb/patcher.py, moonshadow565/rman lib/rlib/rmanifest.cpp) :
//   en-tête 28 octets : "RMAN", version 2.0|2.1, flags u16, offset du corps u32, taille compressée u32,
//                       id du manifest u64, taille décompressée u32 ; corps = une trame zstd.
//   corps FlatBuffers, table racine : 0 bundles, 1 langues, 2 fichiers, 3 répertoires, 4 clés, 5 params.
// INVARIANT : lecture seule d'un tableau d'octets ; toute incohérence lève InvalidDataException, jamais de
// résultat partiel.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace HexLauncher {
    public sealed class RmanHeader {
        public const int Length = 28;
        public byte Major { get; private set; }
        public byte Minor { get; private set; }
        public int BodyOffset { get; private set; }
        public int BodyCompressedLength { get; private set; }
        public ulong ManifestId { get; private set; }
        public int BodyUncompressedLength { get; private set; }

        public string ManifestIdHex { get { return ManifestId.ToString("X16"); } }

        public static RmanHeader Parse(byte[] data) {
            if (data == null || data.Length < Length || Encoding.ASCII.GetString(data, 0, 4) != "RMAN")
                throw new InvalidDataException("RMAN : en-tête absent");
            var header = new RmanHeader {
                Major = data[4],
                Minor = data[5],
                BodyOffset = BitConverter.ToInt32(data, 8),
                BodyCompressedLength = BitConverter.ToInt32(data, 12),
                ManifestId = BitConverter.ToUInt64(data, 16),
                BodyUncompressedLength = BitConverter.ToInt32(data, 24)
            };
            // Les seules versions dont la structure est connue : une 2.2 ou une 3.x peut tout déplacer
            if (header.Major != 2 || header.Minor > 1)
                throw new InvalidDataException("RMAN : version " + header.Major + "." + header.Minor + " non prise en charge");
            if (header.BodyOffset < Length || header.BodyCompressedLength < 0 || header.BodyUncompressedLength < 0
                || (long)header.BodyOffset + header.BodyCompressedLength > data.Length)
                throw new InvalidDataException("RMAN : corps hors du fichier");
            return header;
        }
    }

    public sealed class RmanChunk {
        public ulong ChunkId { get; internal set; }
        public ulong BundleId { get; internal set; }
        public long BundleOffset { get; internal set; }
        public int CompressedSize { get; internal set; }
        public int UncompressedSize { get; internal set; }
        public string BundleIdHex { get { return BundleId.ToString("X16"); } }
    }

    public sealed class RmanFile {
        public string Path { get; internal set; }
        public long Size { get; internal set; }
        public ulong LanguageMask { get; internal set; }
        public ulong[] ChunkIds { get; internal set; }
    }

    public sealed class RmanManifest {
        // Racine du corps
        const int RootBundles = 0, RootLanguages = 1, RootFiles = 2, RootDirectories = 3, RootParams = 5;
        // Champs des tables
        const int BundleId = 0, BundleChunks = 1;
        const int ChunkId = 0, ChunkCompressedSize = 1, ChunkUncompressedSize = 2;
        const int LanguageId = 0, LanguageName = 1;
        const int FileDirectoryId = 1, FileSize = 2, FileName = 3, FileLanguageMask = 4, FileChunkIds = 7;
        const int DirectoryId = 0, DirectoryParentId = 1, DirectoryName = 2;
        const int ParamsHashType = 1;

        readonly Dictionary<ulong, RmanChunk> chunks = new Dictionary<ulong, RmanChunk>();
        readonly Dictionary<string, RmanFile> files = new Dictionary<string, RmanFile>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<byte, string> languages = new Dictionary<byte, string>();

        // 1 SHA-512, 2 SHA-256, 3 RITO_HKDF, 4 BLAKE3 ; 0 = aucun params déclaré
        public int HashType { get; private set; }
        public int FileCount { get { return files.Count; } }
        public IDictionary<byte, string> Languages { get { return languages; } }

        RmanManifest() { }

        public static RmanManifest Parse(byte[] body) {
            try {
                var manifest = new RmanManifest();
                var root = FlatTable.Root(body);
                manifest.ReadBundles(root);
                manifest.ReadLanguages(root);
                manifest.ReadFiles(root, ReadDirectories(root));
                manifest.HashType = ReadHashType(root);
                return manifest;
            }
            catch (InvalidDataException) { throw; }
            catch (Exception e) {
                // Décalage hors du tampon, répertoire inconnu, débordement : un corps corrompu, jamais un bug à masquer
                throw new InvalidDataException("RMAN : corps illisible (" + e.Message + ")", e);
            }
        }

        // Chemin relatif à la racine du produit, séparateur « / », casse ignorée ; null si absent
        public RmanFile FindFile(string path) {
            RmanFile file;
            return files.TryGetValue(path.Replace('\\', '/'), out file) ? file : null;
        }

        public bool HasLanguage(RmanFile file, string language) {
            foreach (var entry in languages)
                if (string.Equals(entry.Value, language, StringComparison.OrdinalIgnoreCase))
                    return entry.Key >= 1 && entry.Key <= 64 && (file.LanguageMask & (1UL << (entry.Key - 1))) != 0;
            return false;
        }

        // Chunks du fichier dans l'ordre de reconstruction
        public RmanChunk[] GetChunks(RmanFile file) {
            var result = new RmanChunk[file.ChunkIds.Length];
            for (int i = 0; i < result.Length; i++) {
                if (!chunks.TryGetValue(file.ChunkIds[i], out result[i]))
                    throw new InvalidDataException("RMAN : chunk " + file.ChunkIds[i].ToString("X16") + " sans bundle");
            }
            return result;
        }

        // L'offset d'un chunk dans son bundle est la somme des tailles compressées de ceux qui le précèdent
        void ReadBundles(FlatTable root) {
            foreach (var bundle in root.Tables(RootBundles)) {
                ulong bundleId = bundle.UInt64(BundleId);
                long offset = 0;
                foreach (var entry in bundle.Tables(BundleChunks)) {
                    var chunk = new RmanChunk {
                        ChunkId = entry.UInt64(ChunkId),
                        BundleId = bundleId,
                        BundleOffset = offset,
                        CompressedSize = (int)entry.UInt32(ChunkCompressedSize),
                        UncompressedSize = (int)entry.UInt32(ChunkUncompressedSize)
                    };
                    chunks[chunk.ChunkId] = chunk;
                    offset += chunk.CompressedSize;
                }
            }
        }

        void ReadLanguages(FlatTable root) {
            foreach (var language in root.Tables(RootLanguages))
                languages[language.Byte(LanguageId)] = language.String(LanguageName);
        }

        static Dictionary<ulong, KeyValuePair<string, ulong>> ReadDirectories(FlatTable root) {
            var directories = new Dictionary<ulong, KeyValuePair<string, ulong>>();
            foreach (var directory in root.Tables(RootDirectories))
                directories[directory.UInt64(DirectoryId)] =
                    new KeyValuePair<string, ulong>(directory.String(DirectoryName) ?? "", directory.UInt64(DirectoryParentId));
            return directories;
        }

        void ReadFiles(FlatTable root, Dictionary<ulong, KeyValuePair<string, ulong>> directories) {
            foreach (var entry in root.Tables(RootFiles)) {
                var file = new RmanFile {
                    Path = BuildPath(entry.String(FileName), entry.UInt64(FileDirectoryId), directories),
                    Size = entry.UInt32(FileSize),
                    LanguageMask = entry.UInt64(FileLanguageMask),
                    ChunkIds = entry.UInt64Vector(FileChunkIds)
                };
                files[file.Path] = file;
            }
        }

        // Répertoire 0 = racine ; la profondeur est bornée pour qu'un cycle ne boucle jamais
        static string BuildPath(string name, ulong directoryId, Dictionary<ulong, KeyValuePair<string, ulong>> directories) {
            var path = name;
            for (int depth = 0; directoryId != 0; depth++) {
                if (depth > 64) throw new InvalidDataException("RMAN : arborescence cyclique");
                var directory = directories[directoryId];
                if (directory.Key.Length > 0) path = directory.Key + "/" + path;
                directoryId = directory.Value;
            }
            return path;
        }

        static int ReadHashType(FlatTable root) {
            foreach (var parameters in root.Tables(RootParams)) return parameters.Byte(ParamsHashType);
            return 0;
        }
    }

    // Table FlatBuffers : soffset vers la vtable, puis champs ; un champ absent vaut sa valeur par défaut (0)
    internal struct FlatTable {
        readonly byte[] data;
        readonly int position;
        readonly int vtable;
        readonly int vtableLength;

        FlatTable(byte[] data, int position) {
            this.data = data;
            this.position = position;
            vtable = position - BitConverter.ToInt32(data, position);
            vtableLength = BitConverter.ToUInt16(data, vtable);
        }

        public static FlatTable Root(byte[] data) {
            return new FlatTable(data, Follow(data, 0));
        }

        static int Follow(byte[] data, int at) {
            return checked(at + (int)BitConverter.ToUInt32(data, at));
        }

        int Field(int index) {
            int slot = 4 + 2 * index;
            if (slot + 2 > vtableLength) return 0;
            int relative = BitConverter.ToUInt16(data, vtable + slot);
            return relative == 0 ? 0 : position + relative;
        }

        public byte Byte(int index) { int at = Field(index); return at == 0 ? (byte)0 : data[at]; }
        public uint UInt32(int index) { int at = Field(index); return at == 0 ? 0 : BitConverter.ToUInt32(data, at); }
        public ulong UInt64(int index) { int at = Field(index); return at == 0 ? 0 : BitConverter.ToUInt64(data, at); }

        public string String(int index) {
            int at = Field(index);
            if (at == 0) return null;
            int start = Follow(data, at);
            return Encoding.UTF8.GetString(data, start + 4, (int)BitConverter.ToUInt32(data, start));
        }

        public ulong[] UInt64Vector(int index) {
            int at = Field(index);
            if (at == 0) return new ulong[0];
            int start = Follow(data, at);
            var values = new ulong[BitConverter.ToUInt32(data, start)];
            for (int i = 0; i < values.Length; i++) values[i] = BitConverter.ToUInt64(data, start + 4 + 8 * i);
            return values;
        }

        public IEnumerable<FlatTable> Tables(int index) {
            int at = Field(index);
            if (at == 0) yield break;
            int start = Follow(data, at);
            uint count = BitConverter.ToUInt32(data, start);
            for (int i = 0; i < count; i++) yield return new FlatTable(data, Follow(data, start + 4 + 4 * i));
        }
    }
}
