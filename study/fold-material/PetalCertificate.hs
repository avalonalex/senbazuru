-- | A continuous certificate for ONE traditional bird petal, starting at the
-- square base. This is a fixture-specific experiment, not a general coupled
-- fold solver. See docs/notes/checked-petal.md for the construction and limits.
--
-- Only three vertices move. With u = tan(t/2)/(1+tan(t/2)), their coordinates
-- are rational functions whose coefficients have the form a + b*sqrt(2).
-- Keeping a and b rational preserves shared-plane zeros exactly. Clearing a
-- common POSITIVE denominator lets polynomial signs bound the entire motion.
-- Bernstein coefficients bound a polynomial on the whole interval. A failed
-- bound means unresolved, never clear; this recipe needs no subdivision.
--
-- The certificate concerns the ideal mathematical sheet. CheckedPetal compares
-- every requested angle-derived Double pose with it under a stated roundoff
-- tolerance. Paper has zero thickness; touching boundaries are allowed.
module PetalCertificate
  ( PetalCertificate (..),
    certifyPetal,
    petalPoints,
    petalMaterial,
    petalFaces,
  )
where

import Control.Monad (unless)
import Data.List (foldl', tails)
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Explain (tshow)
import Senbazuru.Geometry.V3 (V3 (..))

-- Exact arithmetic in Q(sqrt(2)). Its sign needs only rational comparisons:
-- for opposite signs compare a^2 with 2*b^2, without approximating sqrt(2).
data Q = Q !Rational !Rational deriving stock (Eq, Show)

instance Num Q where
  Q a b + Q c d = Q (a + c) (b + d)
  Q a b * Q c d = Q (a * c + 2 * b * d) (a * d + b * c)
  negate (Q a b) = Q (-a) (-b)
  fromInteger n = Q (fromInteger n) 0
  abs x = if x < 0 then negate x else x
  signum x = case compare x 0 of LT -> -1; EQ -> 0; GT -> 1

instance Ord Q where
  compare (Q a b) (Q c d) = sign (a - c) (b - d)
    where
      sign x y
        | y == 0 = compare x 0
        | x == 0 = compare y 0
        | x > 0 && y > 0 = GT
        | x < 0 && y < 0 = LT
        | x > 0 = compare (x * x) (2 * y * y)
        | otherwise = compare (2 * y * y) (x * x)

-- Callers establish a nonzero divisor: positive path denominators, a nonempty
-- clipped polygon, or two strictly different signed distances at a crossing.
quotient :: Q -> Q -> Q
quotient (Q a b) (Q c d) = Q ((a * c - 2 * b * d) / den) ((b * c - a * d) / den)
  where
    den = c * c - 2 * d * d

approx :: Q -> Double
approx (Q a b) = fromRational a + fromRational b * sqrt 2

type Poly = [Q]

type Path = (Poly, Poly, Poly)

type Point = (Q, Q, Q)

add :: Poly -> Poly -> Poly
add [] b = b
add a [] = a
add (a : as) (b : bs) = (a + b) : add as bs

neg :: Poly -> Poly
neg = map negate

mul :: Poly -> Poly -> Poly
mul [] _ = []
mul (a : as) b = add (map (a *) b) (0 : mul as b)

scale :: Q -> Poly -> Poly
scale x = map (x *)

value :: Q -> Poly -> Q
value t = foldr (\x acc -> x + t * acc) 0

restrict :: Q -> Q -> Poly -> Poly
restrict lo hi = foldr (\x acc -> add [x] (mul [lo, hi - lo] acc)) []

bernstein :: Poly -> [Q]
bernstein p = [sum [a * Q (choose k j / choose n j) 0 | (j, a) <- zip [0 .. k] p] | k <- [0 .. n]]
  where
    n = length p - 1
    choose a b = product [fromIntegral (a - b + 1) .. fromIntegral a] / product [1 .. fromIntegral b]

nonnegative :: Poly -> Bool
nonnegative = all (>= 0) . bernstein

-- Every Bernstein basis function is positive on the OPEN interval. One
-- positive coefficient therefore permits zero at a flat endpoint, but nowhere
-- inside. The endpoints are checked separately, including their layer order.
positiveInside :: Poly -> Bool
positiveInside p = let bs = bernstein p in all (>= 0) bs && any (> 0) bs

plus :: Path -> Path -> Path
plus (a, b, c) (d, e, f) = (add a d, add b e, add c f)

minus :: Path -> Path -> Path
minus a (d, e, f) = plus a (neg d, neg e, neg f)

dotP :: Path -> Path -> Poly
dotP (a, b, c) (d, e, f) = add (add (mul a d) (mul b e)) (mul c f)

crossP :: Path -> Path -> Path
crossP (a, b, c) (d, e, f) = (add (mul b f) (neg (mul c e)), add (mul c d) (neg (mul a f)), add (mul a e) (neg (mul b d)))

normal :: [Path] -> Path
normal (a : b : c : _) = crossP (minus b a) (minus c a)
normal _ = ([], [], [])

constant :: Point -> Path
constant (x, y, z) = ([x], [y], [z])

at :: Q -> Path -> Point
at t (x, y, z) = (value t x, value t y, value t z)

diagonal, k2, c2, ck :: Q
diagonal = Q 0 (1 / 2)
k2 = Q (1 / 2) (-(1 / 4))
c2 = Q (1 / 2) (1 / 4)
ck = Q 0 (1 / 4)

petalFaces :: [[Int]]
petalFaces = [[0, 4, 9], [4, 1, 9], [1, 5, 10], [5, 2, 10], [2, 6, 11], [6, 3, 11], [3, 7, 12], [7, 0, 12], [0, 8, 12], [8, 0, 9], [8, 2, 11], [2, 8, 10], [8, 9, 10], [9, 1, 10], [8, 11, 12], [11, 3, 12]]

material :: [Point]
material = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0), (h, 0, 0), (1, h, 0), (h, 1, 0), (0, h, 0), (h, h, 0), (h, diagonal - h, 0), (1 + h - diagonal, h, 0), (h, 1 + h - diagonal, 0), (diagonal - h, h, 0)]
  where
    h = Q (1 / 2) 0

petalMaterial :: [V3]
petalMaterial = map pointDouble material

-- All numerators use D = ((1-u)^2+u^2)*((1-u)^2+k^2*u^2).
-- D is strictly positive even at u=0 and u=1. The tip and shoulders follow
-- circles at different speeds; these are not interpolated vertex positions.
denominator :: Poly
denominator = mul dt ds

dt, ds :: Poly
dt = [1, -2, 2]
ds = [1, -2, 1 + k2]

paths :: Bool -> [Path]
paths above = zipWith make [0 :: Int ..] resting
  where
    h = Q (1 / 2) 0
    a = (1, 0, 0)
    p = (h, diagonal - h, 0)
    q = (1 + h - diagonal, h, 0)
    resting = [a, a, a, a, (h, 0, 0), (1, h, 0), (1, h, 0), (h, 0, 0), (h, h, 0), p, q, q, p]
    height = if above then 1 else -1
    tip = (mul ds (add (scale (1 - diagonal * h) dt) (scale (diagonal * h) [1, -2])), mul ds (add (scale (diagonal * h) dt) (scale (-(diagonal * h)) [1, -2])), scale height (mul ds [0, 1, -1]))
    wx = mul dt (add (scale (1 - c2 * h) ds) (scale (-(k2 * h)) [1, -2, 1 - k2]))
    wy = mul dt (scale ck [0, 0, k2])
    -- 1-cos(s) = 2*k^2*u^2 / Ds.
    wz = scale (height * k2) (mul dt [0, 1, -1])
    make 1 _ = tip
    make 4 _ = (wx, wy, wz)
    make 5 _ = (add denominator (neg wy), add denominator (neg wx), wz)
    make _ (x, y, z) = (scale x denominator, scale y denominator, scale z denominator)

pointDouble :: Point -> V3
pointDouble (x, y, z) = V3 (approx x) (approx y) (approx z)

petalPoints :: Double -> [V3]
petalPoints degrees =
  let half = degrees * pi / 360
      u = if degrees == 180 then 1 else sin half / (sin half + cos half)
      t = Q (toRational u) 0
      den = value t denominator
   in [pointDouble (quotient x den, quotient y den, quotient z den) | path <- paths True, let (x, y, z) = at t path]

data PetalCertificate = PetalCertificate
  { petalIntervals :: !Int,
    petalPairs :: !Int,
    petalEndpointOrders :: !Int,
    petalEdges :: !Int
  }
  deriving stock (Eq, Show)

-- | Check this particular ideal path. The Boolean chooses above/below the
-- packet so tests can reject the reflected, length-preserving wrong route.
-- Orders are (lower, upper); their transitive consequences are included.
certifyPetal :: Bool -> [(Int, Int)] -> Either Text PetalCertificate
certifyPetal above requirements = do
  unless (all (\(a, b) -> a >= 0 && a < 16 && b >= 0 && b < 16 && a /= b && (b, a) `notElem` orders) orders) (Left "petal layer orders are invalid or cyclic")
  unless (positiveInside denominator && value 0 denominator > 0 && value 1 denominator > 0) (Left "petal denominator is not positive")
  unless (all nondegenerate petalFaces) (Left "petal contains a degenerate material panel")
  mapM_ checkLength edges
  endpointCounts <- traverse checkEndpoint [0, 1]
  let unresolved = [(i, j) | (i, j, a, b) <- pairs, not (fixed i && fixed j), not (separated a b)]
  unless (null unresolved) (Left ("petal contact unresolved for panels " <> tshow unresolved))
  pure (PetalCertificate 1 (length pairs) (sum endpointCounts) (length edges))
  where
    orders = S.toList (close (S.fromList requirements))
    close xs = let more = S.union xs (S.fromList [(a, c) | (a, b) <- S.toList xs, (bb, c) <- S.toList xs, b == bb]) in if more == xs then xs else close more
    ps = paths above
    pick vertices ids = [p | (i, p) <- zip [0 ..] vertices, i `elem` ids]
    nondegenerate ids = let n = normal (pick (map constant material) ids) in value 0 (dotP n n) > 0
    faces = map (pick ps) petalFaces
    indexed = zip3 [0 :: Int ..] petalFaces faces
    pairs = [(i, j, a, b) | (i, _, a) : rest <- tails indexed, (j, _, b) <- rest]
    moving = any (`elem` [1, 4, 5])
    fixed i = maybe False (not . moving) (lookup i (zip [0 ..] petalFaces))
    edges = [(i, j) | i <- [0 .. 12], j <- [i + 1 .. 12], any (\vs -> i `elem` vs && j `elem` vs) petalFaces]
    get vertices i = maybe (Left ("missing petal vertex " <> tshow i)) Right (lookup i (zip [0 :: Int ..] vertices))
    checkLength (i, j) = do
      a <- get ps i
      b <- get ps j
      ma <- get (map constant material) i
      mb <- get (map constant material) j
      let v = minus a b
          m = minus ma mb
          squared = value 0 (dotP m m)
      unless (all (== 0) (add (dotP v v) (neg (scale squared (mul denominator denominator))))) (Left ("petal changes material edge " <> tshow (i, j)))
    checkEndpoint end = do
      let den = value end denominator
          points p = let (x, y, z) = at end p in (quotient x den, quotient y den, quotient z den)
      counts <-
        traverse
          ( \(i, j, a, b) -> case overlap (map points a) (map points b) of
              Nothing -> Right 0
              Just xy -> do
                (lower, upper) <- if (i, j) `elem` orders then Right (a, b) else if (j, i) `elem` orders then Right (b, a) else Left ("missing endpoint order " <> tshow (approx end, i, j))
                unless (fixed i && fixed j || approach end xy lower upper > 0) (Left ("petal approaches endpoint against layer order " <> tshow (i, j) <> " at " <> tshow (approx end)))
                Right 1
          )
          pairs
      pure (sum counts)

-- Strict separation of triangle INTERIORS permits seams and point/edge touch.
-- One vertex strictly off the separating plane makes every interior point of
-- that triangle strictly off it. No adjacent triangle pair is simply skipped.
separated :: [Path] -> [Path] -> Bool
separated as bs = any plane (planes as ++ planes bs)
  where
    planes points = case points of
      a : b : c : _ -> let n = normal points in (n, a) : [(crossP n (minus y x), x) | (x, y) <- [(a, b), (b, c), (c, a)]]
      _ -> []
    plane (n, o) = side n o as bs || side n o bs as
    side n o a b = let av = map (dotP n . (`minus` o)) a; bv = map (neg . dotP n . (`minus` o)) b in all nonnegative (av ++ bv) && any positiveInside (av ++ bv)

-- At an endpoint with area overlap, compare plane heights at an exact point
-- inside that overlap. The first nonzero Taylor coefficient gives the sign
-- just inside the motion, even when the gap itself is zero at the endpoint.
approach :: Q -> (Q, Q) -> [Path] -> [Path] -> Q
approach end (x, y) lower upper =
  let height points = case points of
        o : _ -> let n@(nx, ny, nz) = normal points in (add (dotP n o) (neg (mul denominator (add (scale x nx) (scale y ny)))), nz)
        _ -> ([], [])
      (a, az) = height lower
      (b, bz) = height upper
      gap = add (mul b az) (neg (mul a bz))
      local = if end == 0 then gap else restrict 1 0 gap
      leading = case dropWhile (== 0) local of c : _ -> signum c; [] -> 0
   in leading * signum (value end az * value end bz)

-- Exact convex clipping at z=0. The centroid of a nonzero-area overlap is
-- strictly inside both panels, so endpoint height comparison is meaningful.
overlap :: [Point] -> [Point] -> Maybe (Q, Q)
overlap aa bb =
  let xy (x, y, _) = (x, y)
      a = map xy aa
      b = map xy bb
      ring xs = zip xs (drop 1 xs ++ take 1 xs)
      area xs = sum [x * v - y * u | ((x, y), (u, v)) <- ring xs]
      orient = signum (area b)
      side (x, y) (u, v) (p, q) = orient * ((u - x) * (q - y) - (v - y) * (p - x))
      clip points (a0, b0) = concatMap (edge a0 b0) (ring points)
      edge a0 b0 (p@(x, y), q@(u, v)) =
        let sp = side a0 b0 p
            sq = side a0 b0 q
            intersect = let f = quotient sp (sp - sq) in (x + f * (u - x), y + f * (v - y))
         in if sp >= 0 && sq >= 0 then [q] else if sp >= 0 then [intersect] else if sq >= 0 then [intersect, q] else []
      result = foldl' clip a (ring b)
   in if area result == 0 then Nothing else Just (quotient (sum (map fst result)) (fromIntegral (length result)), quotient (sum (map snd result)) (fromIntegral (length result)))
