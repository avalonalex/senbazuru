"""Pixel difference between two renders: mean absolute error and the number of
pixels whose largest channel difference exceeds 3% (8/255)."""
import sys
import numpy as np
from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert("RGB"), float)
b = np.asarray(Image.open(sys.argv[2]).convert("RGB"), float)
d = np.abs(a - b).max(-1)
print(f"{sys.argv[1].split('/')[-1]} vs {sys.argv[2].split('/')[-1]}: MAE {np.abs(a-b).mean()/255*100:.3f}%  px>3% {int((d > 0.03*255).sum())}  px>10% {int((d > 0.10*255).sum())}")
