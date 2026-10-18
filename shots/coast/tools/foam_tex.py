# Tileable foam pattern: multi-octave Worley (F2-F1 web) -> grayscale
import math, random, sys
from PIL import Image
N = 512; random.seed(3)
def worley(cells):
    pts = [[(random.random(), random.random()) for _ in range(cells)] for _ in range(cells)]
    out = [[0.0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            u = x / N * cells; v = y / N * cells
            ci, cj = int(u), int(v)
            f1 = f2 = 9.0
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    i, j = ci + di, cj + dj
                    p = pts[j % cells][i % cells]
                    d = math.hypot(i + p[0] - u, j + p[1] - v)
                    if d < f1: f2 = f1; f1 = d
                    elif d < f2: f2 = d
            out[y][x] = f2 - f1
    return out
a = worley(10); b = worley(23); c = worley(47)
img = Image.new('L', (N, N)); p = img.load()
for y in range(N):
    for x in range(N):
        w = 1 - min(1, a[y][x] * 3.0)
        w2 = 1 - min(1, b[y][x] * 3.5)
        w3 = 1 - min(1, c[y][x] * 3.0)
        v = max(w ** 3 * 0.9, w2 ** 4 * 0.8) * (0.55 + 0.45 * w3) + 0.25 * w3 ** 6
        p[x, y] = int(max(0, min(1, v)) * 255)
img.save(sys.argv[1])
