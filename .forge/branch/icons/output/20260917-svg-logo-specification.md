# hex-launcher-logo.svg — spécification exacte (2026-09-17)

Fichier : `output/20260916-hex-launcher-logo.svg` · `viewBox="0 0 256 256"` · fond transparent · palette fermée.
Toutes les cotes ci-dessous sont en **px de l'espace 256** sauf mention « espace 512 ».

## Palette
| Nom | Hex | Usage |
|---|---|---|
| GOLD | `#FDC92E` | faces (lettres, cadre, anneau de la gemme, dôme des écrous) |
| CHAMFER | `#D9960F` | chanfreins, ombres portées, base des écrous, anneau contre la pierre du cadre… |
| DARK | `#010512` | liserés et contours (cadre, lettres), contour de la gemme, facettes ombrées |
| GEM | `#0185FD` | pierre |
| blanc | `#FFFFFF` | éclats (opaques ou à 0,88–0,90 sur les faces) |

Lumière : **haut, légèrement gauche** (−105° pour la gemme ; décalages haut-gauche pour les biseaux).

## Principe de matière (identique pour cadre, lettres, anneau de gemme)
Pour une forme S :
1. S remplie CHAMFER ;
2. liseré DARK = trait de largeur 2×w centré sur le bord de S, **découpé à S** (moitié intérieure visible = w) ;
3. face F = S érodée de (w + retrait de base) ;
4. copie de F en **blanc** décalée vers la lumière de (dx + éclat_w, dy + éclat_h), puis copie de F en **GOLD** décalée de (dx, dy), toutes deux découpées à l'intérieur du liseré.
Résultat : chanfrein fin + éclat blanc côté lumière, chanfrein large côté ombre.

## 1. Cadre (`<g id="frame">`)
Carré arrondi : marge 7, rayon extérieur 40, épaisseur 13 (de l'inset 0 à l'inset 13 ; inset = distance au bord du carré de marge, rayon = 40 − inset).
| Couche | Géométrie |
|---|---|
| base DARK | anneau insets 0 → 13 (liserés extérieur 1,0 et intérieur 1,5 en résultent) |
| clip | anneau insets 1,0 → 11,5 |
| CHAMFER | anneau 1,0 → 11,5 |
| blanc 0,9 | anneau face insets 4,0 → 8,5, translaté (−2,5, −2,5) |
| GOLD | même anneau face, translaté (−1,0, −1,0) |
Paramètres : `FRAME_OUTLINE_OUT 1.0`, `FRAME_OUTLINE_IN 1.5`, `FRAME_BAND 3.0`, `FRAME_DX/DY 1.0`, `FRAME_SHINE_W/H 1.5`.
Bord intérieur du trou (zone du drapeau) : carré arrondi inset 13 → offset 20 du bord de l'icône, rayon 27.

## 2. Lettres HL (`<g id="logo" transform="scale(0.5)">`)
- **Silhouette** : tracé potrace de la silhouette de `tmp/my drawings/nouveau logo simple.png` (512 px, zone = carré arrondi intérieur du cadre en retrait de 2 px, taches < 40 px écartées, fermeture/ouverture 1 px). Le chemin est stocké tel quel dans le SVG (`<path id="silhouette">`, unités potrace : espace 512 × 10, transform `translate(0,512) scale(0.1,-0.1)`). **Il n'est pas descriptible numériquement : le SVG est la source.**
- Unités : 1 px (256) = 20 unités potrace.
- Contour DARK : `stroke-width 96` (= 2 × 2,4 px) découpé à la silhouette → 2,4 px visibles.
- Face : silhouette érodée de (2,4 + 6,0) × 2 = 16,8 px (espace 512) par érosion octogonale, tracée potrace.
- Borne des copies : silhouette érodée de (2,4 + 0,5) × 2 px, tracée potrace (`inner-clip`).
- Copie blanche (0,9) translatée (−(0,5 + 2,0) × 20, +(0 + 2,5) × 20) = (−50, +50) unités → 2,5 px gauche, 2,5 px haut.
- Copie GOLD translatée (−10, 0) unités → 0,5 px gauche.
- Chanfreins visibles : gauche 6 − 0,5 − 2 = **3,5** ; haut 6 − 0 − 2,5 = **3,5** ; droite 6 + 0,5 = **6,5** ; bas **6,0**. Éclat blanc : 2,0 (gauche) / 2,5 (haut).
Paramètres : `OUTLINE_W 2.4`, `CHAMFER_W 6.0`, `BEVEL_DX 0.5`, `BEVEL_DY 0.0`, `SHINE_W 2.0`, `SHINE_H 2.5`.

## 3. Écrous (2, espace 512 dans le groupe scale 0.5)
Centres mesurés sur le dessin : (180,5 ; 278,5) et (253,5 ; 278,5), rayon 6,5 × 0,85 = **5,525** (→ 2,76 px à 256, centres (90,25 ; 139,25) et (126,75 ; 139,25)).
Pour chaque écrou de centre (x, y), rayon r :
| Couche | Forme |
|---|---|
| ombre CHAMFER | cercle centre (x + 0,09 r ; y + 0,34 r), rayon 1,2 r |
| base CHAMFER | cercle (x ; y), rayon r |
| dôme GOLD | cercle (x − 0,05 r ; y − 0,2 r), rayon 0,75 r |
| éclat blanc | ellipse (x − 0,12 r ; y − 0,45 r), rx 0,5 r, ry 0,24 r |

## 4. Gemme (`<g id="gem">`, espace 256)
Centre **(108,25 ; 139,75)**, rayon **gr = 10,25** (mesuré sur le dessin : disque bleu 512 → (216,5 ; 279,5), r 20,5).
`BEZEL_IN 1.6` (contour noir), `BEZEL_W 1.8` (anneau métal) → R = gr + 3,4 = 13,65.
| Couche | Forme |
|---|---|
| ombre portée CHAMFER | cercle (gx + 0,3 ; gy + 0,6), rayon R + 0,8 |
| anneau CHAMFER | cercle (gx ; gy), rayon R |
| éclat blanc | cercle (gx − 0,6 ; gy − 0,6), rayon R − 0,7 |
| anneau GOLD | cercle (gx − 0,15 ; gy − 0,15), rayon R − 0,6 |
| contour DARK | cercle (gx ; gy), rayon gr + 1,6 |
| pierre GEM | cercle (gx ; gy), rayon gr |
Facettes (polygones sur la pierre) : hexagone extérieur rayon 0,97 gr et table rayon 0,52 gr, tous deux à rotation 0 (sommets à 0°, 60°, … → arêtes haute et basse horizontales). Pour la facette k (quadrilatère sommets extérieurs k, k+1 et table k+1, k), direction θ = angle du milieu de l'arête extérieure ; `dot = cos(θ − (−105°))` :
- `dot > 0,9` → blanc 0,88 ; sinon `dot > 0` → blanc 0,10 + 0,45·√dot ; `dot < 0` → DARK 0,08 + 0,30·√(−dot) ; `dot = 0` → blanc 0,10.
- Table : blanc 0,28.
- Éclat : quadrilatère sur l'arête haut-gauche de la table (sommets à 180° et 240°) rentré de 32 % vers le centre, blanc 0,85.

## 5. Ordre de dessin
`frame` → `logo` (silhouette CHAMFER, contour, copies blanche puis or, écrous) → `gem` (ombre, anneau, éclat, or, contour, pierre, facettes).

## 6. Régénération
Dans le dépôt (suivi par git, hors release) : `python tools/logo/make-logo-svg.py [--preview DOSSIER]` (Python 3, Pillow, numpy ; `potrace` et `resvg` dans le PATH — `scoop install potrace resvg`). Entrée : `tools/logo/hex-launcher-logo-drawing.png` (copie du dessin de référence). Sortie : `tools/logo/hex-launcher-logo.svg`. Le script en annexe ci-dessous est la version de session ; la version maintenue est celle de `tools/logo/`.

## 7. Script de génération (copie intégrale)
```python
"""Génère hex-launcher-logo.svg : cadre or + monogramme HL + gemme, fond transparent (le drapeau se compose derrière).
Silhouette des lettres vectorisée (potrace) depuis « nouveau logo simple.png » ; tout le reste est géométrique.
Matière commune : liseré bleu nuit, chanfrein or sombre côté ombre, éclat blanc côté lumière (haut, légèrement gauche), face or.
Dépendances : Python 3 + Pillow + numpy, potrace et resvg dans le PATH. À lancer depuis la racine du dépôt."""
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, subprocess, re

SRC = 'tmp/my drawings/nouveau logo simple.png'
OUT = 'tmp/flat_icons/hex-launcher-logo.svg'
WORK = 'tmp/flat_icons/trace'
import os; os.makedirs(WORK, exist_ok=True)

PALETTE = {'face': (253, 201, 46), 'chamfer': (217, 150, 15), 'dark': (1, 5, 18), 'gem': (1, 133, 253), 'stud': (163, 114, 16)}
GOLD, CHAMFER, DARK, GEM, STUD = '#FDC92E', '#D9960F', '#010512', '#0185FD', '#D9960F'
SIZE, MARGIN, RADIUS, THICK = 256, 7, 40, 13
LOGO_REGION = (46, 150, 466, 466)          # zone du logo dans l'image 512 (hors cadre)

im = np.array(Image.open(SRC).convert('RGBA')).astype(int)
H, W = im.shape[:2]
rgb, alpha = im[:, :, :3], im[:, :, 3]
names = list(PALETTE)
dist = np.stack([((rgb - np.array(c)) ** 2).sum(axis=2) for c in PALETTE.values()], axis=2)
cls = dist.argmin(axis=2)
opaque = alpha > 128
# Zone intérieure du cadre (carré arrondi, en retrait de quelques px) : rien du cadre n'entre dans les masques du logo
_inset, _radius = (MARGIN + THICK) * 2 + 4, (RADIUS - THICK) * 2 - 4
_region_img = Image.new('L', (W, H), 0)
ImageDraw.Draw(_region_img).rounded_rectangle((_inset, _inset, W - _inset, H - _inset), radius=_radius, fill=255)
region = np.array(_region_img) > 0; region[:LOGO_REGION[1], :] = False
def is_class(*ns): return opaque & region & np.isin(cls, [names.index(n) for n in ns])

def clean(mask, r=1):
    img = Image.fromarray((mask * 255).astype(np.uint8))
    k = 2 * r + 1
    img = img.filter(ImageFilter.MaxFilter(k)).filter(ImageFilter.MinFilter(k))   # fermeture
    img = img.filter(ImageFilter.MinFilter(k)).filter(ImageFilter.MaxFilter(k))   # ouverture
    return np.array(img) > 0

def trace(mask, name, turd=40, alphamax=1.0):
    pbm = f'{WORK}/{name}.pbm'; svg = f'{WORK}/{name}.svg'
    Image.fromarray(((~mask) * 255).astype(np.uint8)).convert('1').save(pbm)
    subprocess.run(['potrace', '-s', '-t', str(turd), '-a', str(alphamax), '-O', '0.2', '-o', svg, pbm], check=True)
    text = open(svg, encoding='utf-8').read()
    return ' '.join(' '.join(d.split()) for d in re.findall(r'<path d="([^"]+)"', text))

def circle_from(mask):
    ys, xs = np.where(mask)
    if len(xs) == 0: return None
    d = max(xs.max() - xs.min(), ys.max() - ys.min()) + 1
    return ((xs.min() + xs.max() + 1) / 2, (ys.min() + ys.max() + 1) / 2, d / 2)

silhouette = clean(is_class('face', 'chamfer', 'dark', 'gem', 'stud'))
inner      = clean(is_class('face', 'chamfer', 'gem', 'stud'))
face       = clean(is_class('face', 'gem', 'stud'))
gem        = circle_from(is_class('gem'))
yy, xx = np.mgrid[0:H, 0:W]
near_gem = ((xx - gem[0]) ** 2 + (yy - gem[1]) ** 2) ** 0.5
stud_mask  = is_class('chamfer') & (near_gem > gem[2] + 2) & (near_gem < gem[2] + 45)   # les clous sont de la couleur du chanfrein
# clous : la plus grosse composante connexe de la classe « clou » de chaque côté de la gemme
def components(mask):
    seen = np.zeros_like(mask); comps = []
    for y0, x0 in zip(*np.where(mask)):
        if seen[y0, x0]: continue
        stack = [(y0, x0)]; seen[y0, x0] = True; pts = []
        while stack:
            y, x = stack.pop(); pts.append((y, x))
            for ny, nx in ((y+1,x),(y-1,x),(y,x+1),(y,x-1)):
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; stack.append((ny, nx))
        comps.append(pts)
    return comps
studs = []
for side in ('left', 'right'):
    m = stud_mask.copy()
    if side == 'left': m[:, int(gem[0]):] = False
    else: m[:, :int(gem[0])] = False
    def is_disc(c):
        ys, xs = zip(*c); w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        return 8 <= w <= 24 and abs(w - h) <= 3 and len(c) / (w * h) > 0.6
    comps = [c for c in components(m) if is_disc(c)]
    if not comps: continue
    pts = max(comps, key=len)
    ys, xs = zip(*pts)
    studs.append(((min(xs) + max(xs) + 1) / 2, (min(ys) + max(ys) + 1) / 2, (max(max(xs) - min(xs), max(ys) - min(ys)) + 1) / 2))

silhouette_d = trace(silhouette, 'outline')
OUTLINE_W, CHAMFER_W = 2.4, 6.0     # contour, et retrait de base de la face (px à 256) ; le chanfrein visible dépend du côté
# Biseaux lus sur la source : chanfrein visible = CHAMFER_W - décalage - éclat côté lumière (3,5 px à gauche et en haut),
# CHAMFER_W + décalage côté ombre (6,5 px à droite, 6 px en dessous) ; éclat blanc entre chanfrein et face côté lumière
BEVEL_DX, BEVEL_DY = 0.5, 0.0       # décalage de la face vers la lumière (gauche, haut)
SHINE_W, SHINE_H = 2.0, 2.5         # éclat blanc sur les flancs gauches et les arêtes hautes
UNIT = 20                            # 1 px à 256 = 2 px à 512 = 20 unités potrace

def erode(mask, radius_px):
    """Érosion quasi circulaire : alternance de voisinages 4 et 8 (octogone)."""
    m = mask.copy()
    for k in range(int(round(radius_px))):
        up, down = np.roll(m, -1, 0), np.roll(m, 1, 0); left, right = np.roll(m, -1, 1), np.roll(m, 1, 1)
        n = m & up & down & left & right
        if k % 2: n &= np.roll(up, -1, 1) & np.roll(up, 1, 1) & np.roll(down, -1, 1) & np.roll(down, 1, 1)
        m = n
    return m

face_d = trace(erode(silhouette, (OUTLINE_W + CHAMFER_W) * 2), 'face', turd=20)
inner_d = trace(erode(silhouette, (OUTLINE_W + 0.5) * 2), 'inner', turd=20)   # tout l'intérieur du contour : borne des copies décalées

# Espace 512 (potrace : translate(0,512) scale(0.1,-0.1)) → espace icône 256
def f(v): return f'{v:.2f}'
# Cadre : anneau en relief, même matière que le logo — liserés sombres, chanfrein, éclat blanc côté lumière, face or.
# Les copies décalées vers le haut-gauche font le biseau : chanfrein fin/éclat sur le bord extérieur haut-gauche
# et sur le bord intérieur bas-droit ; chanfrein large sur le bord extérieur bas-droit et le bord intérieur haut-gauche.
FRAME_OUTLINE_OUT, FRAME_OUTLINE_IN = 1.0, 1.5     # liserés sombres extérieur / intérieur
FRAME_BAND = 3.0                                   # retrait de base de la face
FRAME_DX, FRAME_DY = 1.0, 1.0                      # décalage de la face vers la lumière
FRAME_SHINE_W, FRAME_SHINE_H = 1.5, 1.5            # éclat blanc

def rounded_square(inset):
    """Carré arrondi à `inset` px du bord du cadre (marge comprise), sens horaire."""
    x0 = MARGIN + inset; x1 = SIZE - MARGIN - inset; r = max(0.0, RADIUS - inset)
    return (f'M {f(x0 + r)} {f(x0)} L {f(x1 - r)} {f(x0)} A {f(r)} {f(r)} 0 0 1 {f(x1)} {f(x0 + r)} '
            f'L {f(x1)} {f(x1 - r)} A {f(r)} {f(r)} 0 0 1 {f(x1 - r)} {f(x1)} '
            f'L {f(x0 + r)} {f(x1)} A {f(r)} {f(r)} 0 0 1 {f(x0)} {f(x1 - r)} '
            f'L {f(x0)} {f(x0 + r)} A {f(r)} {f(r)} 0 0 1 {f(x0 + r)} {f(x0)} Z')

def ring(inset_outer, inset_inner):
    return rounded_square(inset_outer) + ' ' + rounded_square(inset_inner)

def frame_svg():
    band_out, band_in = FRAME_OUTLINE_OUT + FRAME_BAND, THICK - FRAME_OUTLINE_IN - FRAME_BAND
    face = ring(band_out, band_in)
    return f'''  <defs>
    <clipPath id="frame-clip"><path d="{ring(FRAME_OUTLINE_OUT, THICK - FRAME_OUTLINE_IN)}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath>
    <path id="frame-face" d="{face}" fill-rule="evenodd"/>
  </defs>
  <g id="frame">
    <path d="{ring(0, THICK)}" fill="{DARK}" fill-rule="evenodd"/>
    <g clip-path="url(#frame-clip)">
      <path d="{ring(FRAME_OUTLINE_OUT, THICK - FRAME_OUTLINE_IN)}" fill="{CHAMFER}" fill-rule="evenodd"/>
      <use href="#frame-face" fill="#FFFFFF" fill-opacity="0.9" transform="translate({f(-(FRAME_DX + FRAME_SHINE_W))},{f(-(FRAME_DY + FRAME_SHINE_H))})"/>
      <use href="#frame-face" fill="{GOLD}" transform="translate({f(-FRAME_DX)},{f(-FRAME_DY)})"/>
    </g>
  </g>'''


gx, gy, gr = gem[0] / 2, gem[1] / 2, gem[2] / 2
BEZEL_IN, BEZEL_W = 1.6, 1.8   # contour noir contre la gemme, largeur de l'anneau de métal (px à 256)

# Gemme taillée (modèle) : table hexagonale à sommets latéraux (arêtes haut et bas horizontales), six facettes autour.
# Lumière à -105° (15° à gauche de la verticale) : facette la plus exposée presque blanche, facettes basses ombrées.
import math
def hexagon(cx, cy, radius, rotation=0):
    return [(cx + radius * math.cos(math.radians(rotation + 60 * k)), cy + radius * math.sin(math.radians(rotation + 60 * k))) for k in range(6)]
def poly(points, fill, opacity):
    pts = ' '.join(f'{f(x)},{f(y)}' for x, y in points)
    return f'    <polygon points="{pts}" fill="{fill}" fill-opacity="{opacity:.2f}"/>'
outer, table = hexagon(gx, gy, gr * 0.97), hexagon(gx, gy, gr * 0.52)
facet_lines = []
for k in range(6):
    a, b = outer[k], outer[(k + 1) % 6]; c, d = table[(k + 1) % 6], table[k]
    angle = math.atan2((a[1] + b[1]) / 2 - gy, (a[0] + b[0]) / 2 - gx)     # direction de la facette (-90° = haut)
    LIGHT = math.radians(-105)                                                # lumière haut-gauche, comme les biseaux des lettres
    dot = math.cos(angle - LIGHT)
    light, shade = max(0.0, dot) ** 0.5, max(0.0, -dot) ** 0.5
    if dot > 0.9: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.88))             # facette face à la lumière : presque blanche
    elif light > 0: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.10 + 0.45 * light))
    elif shade > 0: facet_lines.append(poly([a, b, c, d], DARK, 0.08 + 0.30 * shade))
    else: facet_lines.append(poly([a, b, c, d], '#FFFFFF', 0.10))
facet_lines.append(poly(table, '#FFFFFF', 0.28))
# Éclat : bande le long de l'arête haut-gauche de la table (entre les sommets à 180° et 240°)
t0, t1 = table[3], table[4]
inward = (gx - (t0[0] + t1[0]) / 2, gy - (t0[1] + t1[1]) / 2); k = 0.32
glint = [t0, t1, (t1[0] + inward[0] * k, t1[1] + inward[1] * k), (t0[0] + inward[0] * k, t0[1] + inward[1] * k)]
facet_lines.append(poly(glint, '#FFFFFF', 0.85))
facets_svg = chr(10).join(facet_lines)
# Écrous (espace 512, dans le groupe scale 0.5) : ombre portée or sombre décalée en bas-droite, dôme or, éclat blanc haut-gauche
STUD_SCALE = 0.85   # un peu plus petits que sur le dessin
def stud_svg_for(x, y, r):
    r = r * STUD_SCALE
    recess = f'    <circle cx="{f(x + r * 0.09)}" cy="{f(y + r * 0.34)}" r="{f(r * 1.2)}" fill="{CHAMFER}"/>'   # ombre portée sous l'écrou seulement, rien au-dessus
    base   = f'    <circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{CHAMFER}"/>'
    light  = f'    <circle cx="{f(x - r * 0.05)}" cy="{f(y - r * 0.2)}" r="{f(r * 0.75)}" fill="{GOLD}"/>'
    shine  = f'    <ellipse cx="{f(x - r * 0.12)}" cy="{f(y - r * 0.45)}" rx="{f(r * 0.5)}" ry="{f(r * 0.24)}" fill="#FFFFFF"/>'
    return chr(10).join((recess, base, light, shine))
stud_svg = '\n'.join(stud_svg_for(x, y, r) for x, y, r in studs)
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">
  <!-- hex-launcher : cadre or plat + monogramme HL vectorisé depuis l'illustration de référence + gemme. Fond transparent. -->
{frame_svg()}
  <defs>
    <path id="silhouette" d="{silhouette_d}"/>
    <clipPath id="inside"><use href="#silhouette"/></clipPath>
    <path id="face" d="{face_d}"/>
    <clipPath id="inner-clip"><path d="{inner_d}"/></clipPath>
  </defs>
  <g id="logo" transform="scale(0.5)">
    <!-- Silhouette du dessin, remplie chanfrein ; contour = trait épais découpé à la silhouette (moitié intérieure visible) -->
    <g transform="translate(0,{H}) scale(0.1,-0.1)" clip-path="url(#inside)">
      <use href="#silhouette" fill="{CHAMFER}"/>
      <use href="#silhouette" fill="none" stroke="{DARK}" stroke-width="{f(2 * OUTLINE_W * UNIT)}" stroke-linejoin="round"/>
      <!-- Biseau : face érodée, copie blanche décalée vers la lumière sous la copie or → éclat sur les flancs gauches et arêtes hautes -->
      <g clip-path="url(#inner-clip)">
        <use href="#face" fill="#FFFFFF" fill-opacity="0.9" transform="translate({f(-(BEVEL_DX + SHINE_W) * UNIT)},{f((BEVEL_DY + SHINE_H) * UNIT)})"/>
        <use href="#face" fill="{GOLD}" transform="translate({f(-BEVEL_DX * UNIT)},{f(BEVEL_DY * UNIT)})"/>
      </g>
    </g>
{stud_svg}
  </g>
  <g id="gem">
    <!-- Sertissage : anneau de métal en relief, blanc et or sombre seulement — ombre portée légère en dessous, chanfrein fin bas-droit, éclat haut-gauche ; contour noir contre la pierre -->
    <circle cx="{f(gx + 0.3)}" cy="{f(gy + 0.6)}" r="{f(gr + BEZEL_IN + BEZEL_W + 0.8)}" fill="{CHAMFER}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr + BEZEL_IN + BEZEL_W)}" fill="{CHAMFER}"/>
    <circle cx="{f(gx - 0.6)}" cy="{f(gy - 0.6)}" r="{f(gr + BEZEL_IN + BEZEL_W - 0.7)}" fill="#FFFFFF"/>
    <circle cx="{f(gx - 0.15)}" cy="{f(gy - 0.15)}" r="{f(gr + BEZEL_IN + BEZEL_W - 0.6)}" fill="{GOLD}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr + BEZEL_IN)}" fill="{DARK}"/>
    <circle cx="{f(gx)}" cy="{f(gy)}" r="{f(gr)}" fill="{GEM}"/>
{facets_svg}
  </g>
</svg>
'''
open(OUT, 'w', encoding='utf-8').write(svg)
subprocess.run(['resvg', '-w', '512', OUT, 'tmp/flat_icons/preview-512.png'], check=True)
for size in (48, 32):
    subprocess.run(['resvg', '-w', str(size), OUT, f'tmp/flat_icons/preview-{size}.png'], check=True)

# Planche : dessin / SVG / superposition / petites tailles sur drapeau
user = Image.open(SRC).convert('RGBA')
svg_img = Image.open('tmp/flat_icons/preview-512.png').convert('RGBA')
over = user.copy(); tint = svg_img.copy(); tint.putalpha(tint.split()[3].point(lambda a: int(a * 0.55))); over.alpha_composite(tint)
def on_bg(img):
    bg = Image.new('RGBA', (512, 512), (40, 40, 46, 255)); bg.alpha_composite(img); return bg
def on_flag(size, zoom):
    flag = Image.new('RGBA', (size, size), (0, 0, 0, 0)); d = ImageDraw.Draw(flag); t = size / 256
    d.rectangle((20*t, 20*t, 92*t, 236*t), fill=(0, 37, 153)); d.rectangle((92*t, 20*t, 164*t, 236*t), fill=(254, 254, 254)); d.rectangle((164*t, 20*t, 236*t, 236*t), fill=(235, 41, 58))
    flag.alpha_composite(Image.open(f'tmp/flat_icons/preview-{size}.png').convert('RGBA'))
    return flag.resize((size * zoom, size * zoom), Image.NEAREST)
small = Image.new('RGBA', (512, 512), (40, 40, 46, 255))
small.alpha_composite(on_flag(48, 1), (20, 20)); small.alpha_composite(on_flag(32, 1), (90, 28))
small.alpha_composite(on_flag(48, 5), (20, 100)); small.alpha_composite(on_flag(32, 5), (300, 120))
sheet = Image.new('RGB', (2048, 512))
for i, img in enumerate((on_bg(user), on_bg(svg_img), on_bg(over), small)): sheet.paste(img.convert('RGB'), (512 * i, 0))
sheet.save('tmp/flat_icons/preview-sheet.png')
# Zoom comparatif : dessin / SVG, ×3 sur le L et un empattement
z = Image.new('RGB', (1440, 480), (40, 40, 46))
for i, img in enumerate((on_bg(user), on_bg(svg_img))):
    z.paste(img.convert('RGB').crop((60, 300, 300, 460)).resize((720, 480), Image.LANCZOS), (720 * i, 0))
z.save('tmp/flat_icons/debug-zoom.png')
g = Image.new('RGB', (1200, 400), (40, 40, 46))
model = Image.open('tmp/proposals/modele/ChatGPT Image 14 sept. 2026, 02_40_47.png').convert('RGB').resize((512, 512), Image.LANCZOS)
for i, img in enumerate((model, on_bg(user).convert('RGB'), on_bg(svg_img).convert('RGB'))):
    g.paste(img.crop((150, 230, 290, 330)).resize((400, 286), Image.LANCZOS), (400 * i, 50))
g.save('tmp/flat_icons/debug-gem.png')
print('gem', gem, 'studs', studs)

```
