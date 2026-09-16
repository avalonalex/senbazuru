-- | Exact directional gaps between the two CURRENT bending panels.
-- Neither panel supplies a fixed reference profile. Project each triangle
-- onto xy; vertices contained in the opposite triangle and edge intersections
-- are all corners of their overlap. Height difference is linear there, so
-- these corners bound the entire overlap, including contacts of zero area.
-- This is a known lower/upper order along z, not general contact discovery.
-- Both panels must remain graphs of height above xy, with their original
-- facing directions. See docs/glossary.md for panels and material vertices.
--
-- Each corner retains weights on BOTH triangles. For a vertex/face contact,
-- its gap derivative uses the face normal. For intersecting projected edges,
-- it uses a normal perpendicular to both 3D edges. Using each triangle's own
-- normal would instead fix the overlap point in space and miss its movement.
-- Exact arithmetic makes tiny movable weights beside holds distinguishable
-- from zero, and shared material vertex contributions cancel by id.
module CreasePairContact
  ( PairContactError (..),
    PairWitness (..),
    PairAudit (..),
    auditPairContact,
    samplePairGaps,
  )
where

import Control.Monad (forM, unless)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Text (Text)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface

type R3 = (Rational, Rational, Rational)

type R2 = (Rational, Rational)

newtype PairContactError = PairContactError Text deriving stock (Eq, Show)

instance Explain PairContactError where explain (PairContactError message) = message

data PairWitness = PairWitness
  { pairGap :: !Rational,
    pairWeights :: !(IM.IntMap Rational),
    pairNormal :: !R3,
    pairLocation :: !R2
  }
  deriving stock (Eq, Show)

data PairAudit = PairAudit
  { pairWitnesses :: ![PairWitness],
    pairMinimum :: !Rational,
    pairMaximum :: !Rational
  }
  deriving stock (Eq, Show)

data Face = Face !((Int, R3), (Int, R3), (Int, R3)) !Rational !R3 !(Rational, Rational, Rational, Rational)

-- | Requires one owner per triangle: 0 is the lower panel, 1 the upper.
-- No geometric tolerance or snapping changes any reported gap.
auditPairContact :: [FaceId] -> MaterialMesh -> Either PairContactError PairAudit
auditPairContact owners mesh = do
  faces <- pairFaces owners mesh
  let witnesses = nub (concat [overlap a b | (FaceId 0, a) <- faces, (FaceId 1, b) <- faces, boxesMeet a b])
  case map pairGap witnesses of
    [] -> Left (PairContactError "the two panels have no projected contact region")
    gaps -> pure (PairAudit witnesses (minimum gaps) (maximum gaps))

-- | Sample the same projected locations on different meshes. Missing overlap
-- is explicit, never a zero gap. This map is descriptive; the exact corner
-- audit, not a finite sample grid, certifies non-crossing over all triangles.
-- Multiple triangles on an edge must agree exactly on their height.
samplePairGaps :: [FaceId] -> MaterialMesh -> [R2] -> Either PairContactError [Maybe Rational]
samplePairGaps owners mesh locations = do
  faces <- pairFaces owners mesh
  let at owner p = case nub [height f p | (side, f) <- faces, side == owner, inside f p] of
        [] -> Right Nothing
        [z] -> Right (Just z)
        _ -> Left (PairContactError "one panel has multiple heights at a sampled location")
  forM locations $ \p -> do
    lower <- at (FaceId 0) p
    upper <- at (FaceId 1) p
    pure ((-) <$> upper <*> lower)

pairFaces :: [FaceId] -> MaterialMesh -> Either PairContactError [(FaceId, Face)]
pairFaces owners mesh = do
  unless (length owners == length (triangles mesh) && all (`elem` [FaceId 0, FaceId 1]) owners && all (`elem` owners) [FaceId 0, FaceId 1]) (Left (PairContactError "pair contact needs both panels and one lower/upper owner per triangle"))
  points <- forM (zip [0 ..] (samples mesh)) $ \(i, p) -> do
    let V3 x y z = position p
    unless (all (\v -> not (isNaN v || isInfinite v)) [x, y, z]) (Left (PairContactError ("pair contact needs finite vertex " <> tshow i)))
    pure (i, (toRational x, toRational y, toRational z))
  let vertices = IM.fromList points
      vertex i = maybe (Left (PairContactError ("pair contact lost vertex " <> tshow i))) (Right . (i,)) (IM.lookup i vertices)
  forM (zip3 [0 :: Int ..] owners (triangles mesh)) $ \(i, owner, (a, b, c)) -> do
    ps <- mapM vertex [a, b, c]
    case map snd ps of
      [p, q, r] -> do
        let n@(_, _, nz) = cross (sub q p) (sub r p)
            xs = [x | (x, _, _) <- [p, q, r]]
            ys = [y | (_, y, _) <- [p, q, r]]
        unless (if owner == FaceId 0 then nz > 0 else nz < 0) (Left (PairContactError ("triangle " <> tshow i <> " must retain its lower/up or upper/down facing direction")))
        pure (owner, Face ((a, p), (b, q), (c, r)) nz (scale (1 / nz) n) (minimum xs, maximum xs, minimum ys, maximum ys))
      _ -> Left (PairContactError "pair contact expected three triangle corners")

boxesMeet :: Face -> Face -> Bool
boxesMeet (Face _ _ _ (a, b, c, d)) (Face _ _ _ (e, f, g, h)) = not (b < e || f < a || d < g || h < c)

-- At a coincident vertex several features can be active. Keep their distinct
-- normals as separate rows; do not guess one derivative across a change of
-- overlap features. Parallel edges contribute their contained endpoints.
overlap :: Face -> Face -> [PairWitness]
overlap lower@(Face _ _ ln _) upper@(Face _ _ un _) =
  [witness lower upper (xy p) un | (_, p) <- corners lower, inside upper (xy p)]
    ++ [witness lower upper (xy p) ln | (_, p) <- corners upper, inside lower (xy p)]
    ++ [ witness lower upper location normal
         | ((_, p), (_, q)) <- ring (corners lower),
           let a = xy (sub q p),
           ((_, r), (_, s)) <- ring (corners upper),
           let b = xy (sub s r),
           let den = cross2 a b,
           den /= 0,
           let t = cross2 (minus2 (xy r) (xy p)) b / den,
           let u = cross2 (minus2 (xy r) (xy p)) a / den,
           t >= 0,
           t <= 1,
           u >= 0,
           u <= 1,
           let location = plus2 (xy p) (times2 t a),
           let normal = scale (1 / den) (cross (sub q p) (sub s r))
       ]

witness :: Face -> Face -> R2 -> R3 -> PairWitness
witness lower upper p normal = PairWitness (height upper p - height lower p) weights normal p
  where
    weights = IM.filter (/= 0) (IM.unionWith (+) (weightsAt upper p) (IM.map negate (weightsAt lower p)))

inside :: Face -> R2 -> Bool
inside f p = all (>= 0) (IM.elems (weightsAt f p))

weightsAt :: Face -> R2 -> IM.IntMap Rational
weightsAt (Face ((i, a), (j, b), (k, c)) determinant _ _) p =
  let wb = cross2 (minus2 p (xy a)) (xy (sub c a)) / determinant
      wc = cross2 (xy (sub b a)) (minus2 p (xy a)) / determinant
   in IM.fromList [(i, 1 - wb - wc), (j, wb), (k, wc)]

height :: Face -> R2 -> Rational
height face p = sum [IM.findWithDefault 0 i (weightsAt face p) * z | (i, (_, _, z)) <- corners face]

corners :: Face -> [(Int, R3)]
corners (Face (a, b, c) _ _ _) = [a, b, c]

xy :: R3 -> R2
xy (x, y, _) = (x, y)

sub :: R3 -> R3 -> R3
sub (a, b, c) (x, y, z) = (a - x, b - y, c - z)

scale :: Rational -> R3 -> R3
scale s (x, y, z) = (s * x, s * y, s * z)

cross :: R3 -> R3 -> R3
cross (a, b, c) (x, y, z) = (b * z - c * y, c * x - a * z, a * y - b * x)

cross2 :: R2 -> R2 -> Rational
cross2 (a, b) (x, y) = a * y - b * x

minus2 :: R2 -> R2 -> R2
minus2 (a, b) (x, y) = (a - x, b - y)

plus2 :: R2 -> R2 -> R2
plus2 (a, b) (x, y) = (a + x, b + y)

times2 :: Rational -> R2 -> R2
times2 s (x, y) = (s * x, s * y)

ring :: [a] -> [(a, a)]
ring ps = zip ps (drop 1 ps ++ take 1 ps)
