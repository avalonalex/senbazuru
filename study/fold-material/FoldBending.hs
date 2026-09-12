-- | Angular preferences on shared material creases and inside panels.
--
-- Two triangles sharing an edge can turn like a door about its hinge without
-- changing their lengths. At a crease (a deliberately folded line) this model
-- prefers an authored rest angle; inside an uncreased panel it prefers zero.
-- These are energies, not rigid angle constraints: conflicting preferences can
-- leave both a bent panel and a crease short of its target.
--
-- Angles are radians, zero is unfolded, and positive means a valley (the two
-- front sides close together). The signed angle comes from material winding,
-- never the camera. At a fully closed fold the two signs describe the same
-- geometry; 'angleError' chooses the branch closest to the prescribed rest.
-- That local convention is suitable for an already posed packet, not a record
-- of motion through 180 degrees.
--
-- Energy is half stiffness times squared angular error. Crease stiffness is
-- distributed by material edge length; panel stiffness uses edge length
-- divided by the mean height of its two triangles. The latter is a simple
-- discrete curvature penalty, not a calibrated paper constitutive law. It
-- must not be interpreted as measured paper thickness or a mesh-independent
-- continuum solution. See docs/notes/crease-and-panel-energy.md.
module FoldBending
  ( Bending (..),
    defaultBending,
    PacketRestAngles (..),
    defaultPacketRestAngles,
    HingeRole (..),
    Hinge (..),
    BendingError (..),
    buildHinges,
    buildSurfaceHinges,
    hingeAngle,
    angleError,
    bendingRows,
    bendingEnergy,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first, second)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import FoldMaterial
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface qualified as Paper

-- | Illustrative resistance, independent of the crease controls. A spring's
-- preferred angle is not the same quantity as the current pose's fold angle.
data Bending = Bending
  { creaseStiffness :: !Double,
    panelStiffness :: !Double
  }
  deriving stock (Eq, Show)

defaultBending :: Bending
defaultBending = Bending 1 5

-- | The original packet controls use positive magnitudes. Their unit-square
-- assignments supply the signs, including the upside-down second-fold layer.
-- Shared-surface callers instead supply signed controls keyed by source EdgeId.
data PacketRestAngles = PacketRestAngles
  { firstRestAngle :: !Double,
    secondRestAngle :: !Double
  }
  deriving stock (Eq, Show)

defaultPacketRestAngles :: PacketRestAngles
defaultPacketRestAngles = PacketRestAngles (170 * pi / 180) (170 * pi / 180)

data HingeRole = FirstCrease | SecondCrease | SurfaceCrease !EdgeId | PanelBend
  deriving stock (Eq, Ord, Show)

data Hinge = Hinge
  { hingeVertices :: !(Int, Int, Int, Int),
    hingeRole :: !HingeRole,
    hingeRest :: !Double,
    hingeStiffness :: !Double
  }
  deriving stock (Eq, Show)

data BendingError
  = InvalidBending
  | SurfaceBendingFailure !Paper.SurfaceError
  | MissingRestAngle !EdgeId
  | UnexpectedRestAngle !EdgeId
  | InvalidRestAngle !EdgeId !Double
  | UnsupportedCrease !EdgeId
  | AmbiguousCreaseSegment !Int !Int
  | MissingHingeVertex !Int
  | InvalidMaterialTriangle !Int
  | InvalidHingeEdge !Int !Int
  | CollapsedHinge !Int !Int
  deriving stock (Eq, Show)

instance Explain BendingError where
  explain InvalidBending = "bending needs finite positive stiffnesses and packet angle magnitudes between 0 and pi"
  explain (SurfaceBendingFailure err) = explain err
  explain (MissingRestAngle eid) = "crease " <> tshow eid <> " needs an explicit signed rest angle; its current pose is not a rest-angle control"
  explain (UnexpectedRestAngle eid) = "rest angle names " <> tshow eid <> ", which is not an active interior crease of this surface"
  explain (InvalidRestAngle eid angle) = "crease " <> tshow eid <> " needs a finite rest angle in [-pi, pi] matching its mountain/valley sign, got " <> tshow angle
  explain (UnsupportedCrease eid) = "crease " <> tshow eid <> " must join two panels and appear as shared edges of the refined mesh"
  explain (AmbiguousCreaseSegment a b) = "mesh edge " <> tshow a <> "–" <> tshow b <> " belongs to more than one source crease"
  explain (MissingHingeVertex i) = "bending hinge refers to missing material vertex " <> tshow i
  explain (InvalidMaterialTriangle i) = "bending triangle " <> tshow i <> " needs finite, counterclockwise material coordinates and positive area"
  explain (InvalidHingeEdge a b) = "bending edge " <> tshow a <> "–" <> tshow b <> " must have at most two consistently wound triangles"
  explain (CollapsedHinge a b) = "bending edge " <> tshow a <> "–" <> tshow b <> " has a collapsed or non-finite spatial triangle"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

-- | Classify the creases of these two unit-square fixtures in MATERIAL space.
-- Boundary edges have no angular spring. Coincident positions never weld two
-- distinct material ids. This deliberately does not infer arbitrary creases.
buildHinges :: Bending -> PacketRestAngles -> FoldCase -> MaterialMesh -> Either BendingError [Hinge]
buildHinges settings targets which mesh = do
  unless (all (\x -> finite x && x >= 0 && x <= pi) [firstRestAngle targets, secondRestAngle targets]) (Left InvalidBending)
  hingesWith settings classify mesh
  where
    classify _ pa pb
      | on materialU = Right (FirstCrease, firstRestAngle targets)
      | which == Double && on materialV =
          let sign = if (materialU pa + materialU pb) / 2 < 0.5 then -1 else 1
           in Right (SecondCrease, sign * secondRestAngle targets)
      | otherwise = Right (PanelBend, 0)
      where
        on coordinate = abs (coordinate pa - 0.5) < 1e-12 && abs (coordinate pb - 0.5) < 1e-12

-- | Refine the surface once, then attach controls to the resulting source-edge
-- segments. Rest angles are radians, in the CUT pattern's edge numbering. The
-- current edges_foldAngle values place the starting sheet; they are never used
-- as implicit rest angles. Every active interior crease needs a control, even
-- an unassigned crease or one whose desired rest angle is zero.
--
-- Boundaries/cuts have no two-sided hinge. Flat panel diagonals stay panel bends.
-- No material coordinate test or spatial coincidence determines ownership.
buildSurfaceHinges :: Bending -> Int -> Paper.Surface V2 -> M.Map EdgeId Double -> Either BendingError (Paper.RefinedSurface, [Hinge])
buildSurfaceHinges settings levels sheet targets = do
  features <- first SurfaceBendingFailure (Paper.surfaceFeatures sheet)
  refined <- first SurfaceBendingFailure (Paper.refineSurfaceWithEdges levels sheet)
  let creases = [(edge, owners) | (edge, owners) <- features, creaseAssignment edge `notElem` [Border, Cut]]
      wanted = S.fromList [creaseId edge | (edge, _) <- creases]
      segments = [(eid, key a b) | (eid, (a, b)) <- Paper.refinedEdges refined, S.member eid wanted]
      represented = S.fromList (map fst segments)
      controls = M.fromListWith (++) [(segment, [(eid, rest)]) | (eid, segment) <- segments, Just rest <- [M.lookup eid targets]]
  mapM_ (\eid -> unless (S.member eid wanted) (Left (UnexpectedRestAngle eid))) (M.keys targets)
  mapM_ (validate represented) creases
  mapM_ (\((a, b), owners) -> unless (length owners == 1) (Left (AmbiguousCreaseSegment a b))) (M.toList controls)
  let classify segment _ _ = case M.lookup segment controls of
        Just [(eid, rest)] -> Right (SurfaceCrease eid, rest)
        _ -> Right (PanelBend, 0)
  hinges <- hingesWith settings classify (Paper.refinedMesh refined)
  let built = S.fromList [key a b | h <- hinges, let (a, b, _, _) = hingeVertices h, SurfaceCrease _ <- [hingeRole h]]
  mapM_ (\(eid, segment) -> unless (S.member segment built) (Left (UnsupportedCrease eid))) segments
  pure (refined, hinges)
  where
    validate represented (edge, owners) = do
      let eid = creaseId edge
      unless (length owners == 2 && S.member eid represented) (Left (UnsupportedCrease eid))
      rest <- maybe (Left (MissingRestAngle eid)) Right (M.lookup eid targets)
      let signOK = case creaseAssignment edge of Mountain -> rest <= 0; Valley -> rest >= 0; _ -> True
      unless (finite rest && abs rest <= pi && signOK) (Left (InvalidRestAngle eid rest))

key :: Int -> Int -> (Int, Int)
key a b = (min a b, max a b)

hingesWith :: Bending -> ((Int, Int) -> MaterialSample -> MaterialSample -> Either BendingError (HingeRole, Double)) -> MaterialMesh -> Either BendingError [Hinge]
hingesWith settings classify mesh = do
  unless (all (\x -> finite x && x > 0) [creaseStiffness settings, panelStiffness settings]) (Left InvalidBending)
  mapM_ validateTriangle (zip [0 ..] (triangles mesh))
  concat <$> mapM build (M.toList incidence)
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    vertex i = maybe (Left (MissingHingeVertex i)) Right (IM.lookup i vertices)
    material s = V3 (materialU s) (materialV s) 0
    validateTriangle (i, (a, b, c)) = do
      points <- mapM vertex [a, b, c]
      case map material points of
        [pa, pb, pc] | let V3 _ _ area = cross (pb ^-^ pa) (pc ^-^ pa), finite area && area > 0 -> Right ()
        _ -> Left (InvalidMaterialTriangle i)
    incidence = M.fromListWith (++) [(key a b, [(a, b, c)]) | (i, j, k) <- triangles mesh, (a, b, c) <- [(i, j, k), (j, k, i), (k, i, j)]]
    build (_, [_]) = Right []
    build ((i, j), [(a, b, c), (b', a', d)]) | a == a' && b == b' = do
      pa <- vertex a
      pb <- vertex b
      pc <- vertex c
      pd <- vertex d
      let edge = material pb ^-^ material pa
          len = norm edge
          twiceArea = norm (cross edge (material pc ^-^ material pa)) + norm (cross edge (material pd ^-^ material pa))
      (role, rest) <- classify (key a b) pa pb
      let weight = if role == PanelBend then panelStiffness settings * 2 * len * len / twiceArea else creaseStiffness settings * len
      if all finite [len, twiceArea, weight] && weight > 0
        then Right [Hinge (a, b, c, d) role rest weight]
        else Left (InvalidHingeEdge i j)
    build ((a, b), _) = Left (InvalidHingeEdge a b)

-- | Signed angle and its derivative with respect to the four positions.
-- The opposite corners move the normals directly. Contributions at the two
-- edge endpoints follow by distributing those motions along the edge; their
-- sum is zero, so translating the whole sheet changes no angle.
hingeAngle :: Hinge -> IM.IntMap MaterialSample -> Either BendingError (Double, [(Int, V3)])
hingeAngle hinge vertices = do
  pa <- point a
  pb <- point b
  pc <- point c
  pd <- point d
  let edge = pb ^-^ pa
      len = norm edge
      leftNormal = cross edge (pc ^-^ pa)
      rightNormal = cross (pd ^-^ pa) edge
      nl = norm leftNormal
      nr = norm rightNormal
  if not (all (\x -> finite x && x > 1e-14) [len, nl, nr])
    then Left (CollapsedHinge a b)
    else do
      let leftUnit = (1 / nl) *^ leftNormal
          rightUnit = (1 / nr) *^ rightNormal
          angle = negate (atan2 (dot ((1 / len) *^ edge) (cross leftUnit rightUnit)) (dot leftUnit rightUnit))
          gc = (len / (nl * nl)) *^ leftNormal
          gd = (len / (nr * nr)) *^ rightNormal
          along p = dot (p ^-^ pa) edge / (len * len)
          gb = (negate (along pc) *^ gc) ^+^ (negate (along pd) *^ gd)
          ga = (-1) *^ (gb ^+^ gc ^+^ gd)
      Right (angle, [(a, ga), (b, gb), (c, gc), (d, gd)])
  where
    (a, b, c, d) = hingeVertices hinge
    point i = maybe (Left (MissingHingeVertex i)) (Right . position) (IM.lookup i vertices)

angleError :: Double -> Double -> Double
angleError actual rest = atan2 (sin (actual - rest)) (cos (actual - rest))

-- | Weighted residuals for least squares. The solver minimises half their
-- squared norm, exactly the energy reported by 'bendingEnergy'.
bendingRows :: [Hinge] -> MaterialMesh -> Either BendingError [([(Int, V3)], Double)]
bendingRows hinges mesh = mapM row hinges
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    row hinge = do
      (angle, gradient) <- hingeAngle hinge vertices
      let weight = sqrt (hingeStiffness hinge)
      Right (map (second (weight *^)) gradient, weight * angleError angle (hingeRest hinge))

-- | Crease and panel contributions, in that order, in illustrative energy units.
bendingEnergy :: [Hinge] -> MaterialMesh -> Either BendingError (Double, Double)
bendingEnergy hinges mesh = do
  rows <- bendingRows hinges mesh
  let contributions = [(hingeRole hinge, residual * residual / 2) | (hinge, (_, residual)) <- zip hinges rows]
  Right (sum [e | (role, e) <- contributions, role /= PanelBend], sum [e | (role, e) <- contributions, role == PanelBend])
