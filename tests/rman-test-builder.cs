// Aide de test : corps RMAN FlatBuffers synthétique, écrit sans schéma ni bibliothèque.
// Disposition « en avant » : chaque objet est suivi de ses enfants, les uoffsets sont donc positifs.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace HexLauncher.Tests {
    public sealed class FlatNode {
        internal readonly SortedDictionary<int, object> Fields = new SortedDictionary<int, object>();
        public FlatNode Set(int index, object value) { Fields[index] = value; return this; }
    }

    public sealed class RmanBodyBuilder {
        readonly List<FlatNode> bundles = new List<FlatNode>();
        readonly List<FlatNode> languages = new List<FlatNode>();
        readonly List<FlatNode> files = new List<FlatNode>();
        readonly List<FlatNode> directories = new List<FlatNode>();
        readonly List<FlatNode> parameters = new List<FlatNode>();

        // chunks : liste plate de triplets chunkId, compressedSize, uncompressedSize (PowerShell aplatit les tableaux imbriqués)
        public RmanBodyBuilder AddBundle(ulong bundleId, ulong[] chunks) {
            var entries = Enumerable.Range(0, chunks.Length / 3)
                .Select(i => new FlatNode().Set(0, chunks[3 * i]).Set(1, (uint)chunks[3 * i + 1]).Set(2, (uint)chunks[3 * i + 2]))
                .ToArray();
            bundles.Add(new FlatNode().Set(0, bundleId).Set(1, entries));
            return this;
        }

        public RmanBodyBuilder AddLanguage(byte id, string name) {
            languages.Add(new FlatNode().Set(0, id).Set(1, name));
            return this;
        }

        public RmanBodyBuilder AddDirectory(ulong id, ulong parentId, string name) {
            var node = new FlatNode().Set(2, name);
            if (id != 0) node.Set(0, id);
            if (parentId != 0) node.Set(1, parentId);
            directories.Add(node);
            return this;
        }

        public RmanBodyBuilder AddFile(ulong directoryId, string name, uint size, ulong languageMask, ulong[] chunkIds) {
            var node = new FlatNode().Set(0, (ulong)(files.Count + 1)).Set(2, size).Set(3, name).Set(7, chunkIds);
            if (directoryId != 0) node.Set(1, directoryId);
            if (languageMask != 0) node.Set(4, languageMask);
            files.Add(node);
            return this;
        }

        public RmanBodyBuilder SetHashType(byte hashType) {
            parameters.Clear();
            parameters.Add(new FlatNode().Set(0, (ushort)0).Set(1, hashType));
            return this;
        }

        public byte[] Build() {
            var root = new FlatNode()
                .Set(0, bundles.ToArray()).Set(1, languages.ToArray()).Set(2, files.ToArray())
                .Set(3, directories.ToArray()).Set(4, new FlatNode[0]).Set(5, parameters.ToArray());
            var output = new MemoryStream();
            long slot = Reserve(output);
            Patch(output, slot, WriteTable(output, root));
            return output.ToArray();
        }

        static long Reserve(MemoryStream output) {
            long at = output.Position;
            output.Write(new byte[4], 0, 4);
            return at;
        }

        static void Patch(MemoryStream output, long slot, long target) {
            long end = output.Position;
            output.Position = slot;
            output.Write(BitConverter.GetBytes((uint)(target - slot)), 0, 4);
            output.Position = end;
        }

        static int SizeOf(object value) {
            if (value is byte) return 1;
            if (value is ushort) return 2;
            if (value is uint) return 4;
            if (value is ulong) return 8;
            return 4;   // référence : chaîne, vecteur
        }

        // vtable, puis table (soffset + champs), puis les enfants référencés ; rend la position de la table
        static long WriteTable(MemoryStream output, FlatNode node) {
            int count = node.Fields.Count == 0 ? 0 : node.Fields.Keys.Max() + 1;
            var offsets = new ushort[count];
            int cursor = 4;
            foreach (var field in node.Fields) { offsets[field.Key] = (ushort)cursor; cursor += SizeOf(field.Value); }
            var writer = new BinaryWriter(output);
            long vtable = output.Position;
            writer.Write((ushort)(4 + 2 * count));
            writer.Write((ushort)cursor);
            foreach (var offset in offsets) writer.Write(offset);
            long table = output.Position;
            writer.Write((int)(table - vtable));
            var references = new List<KeyValuePair<long, object>>();
            foreach (var field in node.Fields) {
                object value = field.Value;
                if (value is byte) writer.Write((byte)value);
                else if (value is ushort) writer.Write((ushort)value);
                else if (value is uint) writer.Write((uint)value);
                else if (value is ulong) writer.Write((ulong)value);
                else { references.Add(new KeyValuePair<long, object>(output.Position, value)); writer.Write(0u); }
            }
            foreach (var reference in references) {
                long target = output.Position;
                WriteReferenced(output, reference.Value);
                Patch(output, reference.Key, target);
            }
            return table;
        }

        static void WriteReferenced(MemoryStream output, object value) {
            var writer = new BinaryWriter(output);
            var text = value as string;
            if (text != null) {
                var bytes = Encoding.UTF8.GetBytes(text);
                writer.Write((uint)bytes.Length); writer.Write(bytes); writer.Write((byte)0);
                return;
            }
            var numbers = value as ulong[];
            if (numbers != null) {
                writer.Write((uint)numbers.Length);
                foreach (var number in numbers) writer.Write(number);
                return;
            }
            var tables = (FlatNode[])value;
            writer.Write((uint)tables.Length);
            var slots = tables.Select(t => Reserve(output)).ToArray();
            for (int i = 0; i < tables.Length; i++) Patch(output, slots[i], WriteTable(output, tables[i]));
        }
    }
}
