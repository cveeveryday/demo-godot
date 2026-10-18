# Generates a tileable ocean detail normal map + height map from a Phillips-like spectrum
# (sum of integer-wavevector sinusoids => perfectly tileable). Pure python.
import math, random, sys
from PIL import Image
N = int(sys.argv[2]) if len(sys.argv) > 2 else 512
out = sys.argv[1]
random.seed(7)
wind = (math.cos(0.4), math.sin(0.4))
waves = []
for kx in range(-64, 65):
    for ky in range(-64, 65):
        k = math.hypot(kx, ky)
        if k < 1.5: continue
        kn = (kx / k, ky / k)
        d = kn[0] * wind[0] + kn[1] * wind[1]
        L = 9.0  # peak wavenumber
        ph = math.exp(-1.0 / (k / L) ** 2) / k ** 3.4 * (abs(d) ** 2 + 0.05)
        if d < 0: ph *= 0.35
        a = math.sqrt(ph) * random.gauss(1, 0.3)
        waves.append((a, kx, ky, random.uniform(0, 2 * math.pi)))
waves.sort(key=lambda w: -abs(w[0]) * math.hypot(w[1], w[2]) * random.uniform(0.5, 1.5))
waves = waves[:420]
print(len(waves), 'waves')
TAU = 2 * math.pi
h = [[0.0] * N for _ in range(N)]
dx = [[0.0] * N for _ in range(N)]
dy = [[0.0] * N for _ in range(N)]
for (a, kx, ky, p) in waves:
    sx = [math.sin(TAU * kx * x / N + p) for x in range(N)]
    cx = [math.cos(TAU * kx * x / N + p) for x in range(N)]
    sy = [math.sin(TAU * ky * y / N) for y in range(N)]
    cy = [math.cos(TAU * ky * y / N) for y in range(N)]
    for y in range(N):
        hy = h[y]; dxy = dx[y]; dyy = dy[y]; s2 = sy[y]; c2 = cy[y]
        for x in range(N):
            s = sx[x] * c2 + cx[x] * s2   # sin(a+b)
            c = cx[x] * c2 - sx[x] * s2   # cos(a+b)
            hy[x] += a * s
            dxy[x] += a * c * kx
            dyy[x] += a * c * ky
# normalise
m = max(max(abs(v) for v in r) for r in h)
gm = max(max(max(abs(v) for v in r) for r in dx), max(max(abs(v) for v in r) for r in dy))
strength = 1.6
img = Image.new('RGB', (N, N)); hi = Image.new('L', (N, N))
pn = img.load(); ph_ = hi.load()
for y in range(N):
    for x in range(N):
        gx = dx[y][x] / gm * strength; gy = dy[y][x] / gm * strength
        l = math.sqrt(gx * gx + gy * gy + 1)
        nx, ny, nz = -gx / l, gy / l, 1 / l   # GL convention (image y down -> flip)
        pn[x, y] = (int((nx * .5 + .5) * 255), int((ny * .5 + .5) * 255), int((nz * .5 + .5) * 255))
        ph_[x, y] = int((h[y][x] / m * .5 + .5) * 255)
img.save(out + '_nrm.png'); hi.save(out + '_height.png')
