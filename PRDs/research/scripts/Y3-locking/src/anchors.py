"""Recover the anchors the pillow construction prescribed for spread-0.

WholeCrane.pillowCraneWith (study code) builds spread-s by
  1. placing every BodyCore vertex on a cushion formula of its material
     coordinates (bodyWidthScale 0.5 for the spread-* family), and
  2. placing every wing vertex with folded y <= 0.25 on a circular arch whose
     root tangent is -(5pi/18) + (s - 0.5)(2pi/9), with a 30-degree turn,
  3. filling everything else with a weighted graph-Laplacian continuation
     (weights 1/rest length), which does not keep lengths.
No relaxation follows. This module re-evaluates 1 and 2 and returns which
vertices match exactly: those are the anchors; the rest were continued.
"""
import numpy as np

R = (np.sqrt(2) - 1) / 2


def cushion(uv, scale=0.5):
    u, v = uv[..., 0], uv[..., 1]
    x = (1 - u - v) / np.sqrt(2)
    z = (u - v) / np.sqrt(2)
    dome = np.maximum(0, 1 - (x / R) ** 2) * np.maximum(0, 1 - (z / R) ** 2)
    return np.stack([1 + x, 0.44 - 0.045 * dome, scale * z], axis=-1)


def arch(before_xy, side, amount=0.0, scale=0.5):
    start = -(5 * np.pi / 18) + (amount - 0.5) * (2 * np.pi / 9)
    x, y = before_xy[..., 0], before_xy[..., 1]
    ln = 0.5 - y
    turn = (np.pi / 6) / 0.5
    ang = start + turn * ln
    return np.stack([x, 0.44 + (np.cos(start) - np.cos(ang)) / turn,
                     side * (scale * R + (np.sin(ang) - np.sin(start)) / turn)], axis=-1)


def find_anchors(X, UV, Xbefore, amount=0.0, tol=1e-9):
    core = np.linalg.norm(X - cushion(UV), axis=1) < tol
    wa = np.linalg.norm(X - arch(Xbefore[:, :2], -1, amount), axis=1) < tol
    wb = np.linalg.norm(X - arch(Xbefore[:, :2], 1, amount), axis=1) < tol
    wing = (wa | wb) & (Xbefore[:, 1] <= 0.25 + 1e-9)
    return core, wing, wa & wing, wb & wing
