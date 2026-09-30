-- | Connected, prescribed whole-crane shapes for visual review.
-- The saved body is a cut-out specimen. Here its material coordinates locate
-- the same paper on the full sheet; original shared vertex ids do the joining,
-- never proximity in the folded stack. The central body is held at its saved
-- shape while neck/head, tail and wings can adjust around it.
--
-- Continue the body's deformation into the missing paper with a smooth graph
-- displacement (neighbouring vertices prefer the same correction). This is an
-- INITIAL GUESS and can strain paper. Both wings then follow a circular bend
-- below y=0.30 in the original folded fixture, clear of the body interface.
-- The bend has zero extra turn at its root and 60 degrees at the tips. It is
-- sampled by triangles, not a rendered curve concealing different geometry.
-- No interpolation here describes a physical folding motion. See the material
-- coordinates and panels in docs/glossary.md.
--
-- 'pillowCrane' provides a separate visual target by releasing that saved body
-- and prescribing a broad, shallow cushion with outward wings. It keeps the
-- same connected material but greatly distorts it. Neither construction is an
-- accepted paper pose; the gallery reports their defects beside the drawings.
--
-- 'wholeCranePoses' lists what the gallery draws, each pose with how its
-- positions were made. Only the closed crane was folded. Every other pose was
-- placed where the crane should be, which makes it a /shape sketch/ (see
-- docs/glossary.md), and its drawings, its GLB and its cards say so. Its FOLD
-- file does not: a fidelity claim is not FOLD data (D19). The list lives
-- here, not in the gallery, so that the test suite can check which pose is
-- which. Because each pose records its construction rather than only its
-- mesh, 'remadeOn' can make the same pose on a finer mesh, which is how the
-- paper screen tells a fold from a curve.
module WholeCrane (WholeCrane (..), CranePose (..), Construction (..), wholeCrane, pillowCrane, compactPillowCrane, narrowPillowCrane, pillowCraneAtSpread, spreadAngle, refinedCrane, remadeOn, cranePose, wholeCraneOpenings, wholeCranePoses, craneGeometry, craneCaveat, withCaveat, studyLevel, wholeMeasurements) where

import BodyPatch
import Control.Monad (unless)
import CranePocket
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import FoldBending
import FoldMaterial (componentCount, meshEdges)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Fidelity (Geometry (..))
import SparseSolve

data WholeCrane = WholeCrane
  { wholeSpread :: !CraneSpread,
    wholeMap :: !PocketMap,
    wholeCore :: !(S.Set Int),
    wholeMarks :: ![(Text, Int)],
    wholeMappedVertices :: !Int
  }
  deriving stock (Show)

wholeCrane :: PocketMap -> BodyPatch -> MaterialMesh -> Either SpreadError WholeCrane
wholeCrane atlas patch saved = do
  unless (patchDegrees patch == 10 && patchLevel patch == 1) (bad "whole crane requires the saved ten-degree refined body")
  _ <- spreadSurface (patchSpread patch) saved
  let sheet = pocketSurface atlas
  (refined, hinges) <- refinedCrane studyLevel atlas
  let base = refinedMesh refined
      tagged = zip (triangles base) (refinedPanels refined)
      memberships = IM.fromListWith S.union [(i, S.singleton r) | (tri, owner) <- tagged, Just r <- [M.lookup owner (pocketRegions atlas)], i <- vertices tri]
      core = S.fromList [i | (tri, owner) <- tagged, owner `elem` regionFaces atlas BodyCore, i <- vertices tri]
      original = IM.fromList (zip [0 ..] (samples base))
      savedSamples = IM.fromList (zip [0 ..] (samples saved))
      savedTriangles = [[p | i <- vertices tri, Just p <- [IM.lookup i savedSamples]] | tri <- triangles saved]
      mapped p = case [q | ps <- savedTriangles, Just q <- [interpolateMaterial (sampleMaterial p) ps]] of
        [] -> Nothing
        q : rest | all ((< 1e-8) . norm . (^-^ q)) rest -> Just q
        _ -> Nothing
      anchors = IM.fromList [(i, q) | (i, p) <- IM.toList original, Just q <- [mapped p]]
  unless (all (`IM.member` anchors) (S.toList core)) (bad "the saved body does not cover every central vertex")
  unless (IM.size anchors == length (samples saved)) (bad "expected matching uniform midpoint material samples on the saved patch")
  -- The two wing fits use their saved attachment shape, not a guessed sign
  -- based on front/back colour. The opened patch already changes their tilt.
  wingFits <- traverse (fitWing memberships original anchors) [WingA, WingB]
  let fits = M.fromList (zip [WingA, WingB] wingFits)
      baseline i p = case S.toList (IM.findWithDefault S.empty i memberships) of
        [r] | Just fit <- M.lookup r fits -> applyFit fit (position p)
        _ -> analytic p
      initial = IM.mapWithKey baseline original
  continued <- continueDisplacements base initial anchors
  let bend i p = case S.toList (IM.findWithDefault S.empty i memberships) of
        [r]
          | Just (_, _, ex, ey) <- M.lookup r fits,
            let len = max 0 (0.30 - v3y (position p)),
            len > 0 ->
              let turn = (pi / 3) / 0.30
                  side = if r == WingA then 1 else -1
                  normal = cross ex ey
               in (len - sin (turn * len) / turn) *^ ey ^+^ (side * (1 - cos (turn * len)) / turn) *^ normal
        _ -> V3 0 0 0
      moved = base {samples = [p {position = IM.findWithDefault (position p) i continued ^+^ bend i p} | (i, p) <- IM.toList original]}
      landmark (name, v) = (name, unVertexId v)
      marks = ("centre", unVertexId (pocketCentre atlas)) : [landmark (regionKey r, v) | (r, v) <- pocketTips atlas]
      tips = S.fromList [unVertexId v | (r, v) <- pocketTips atlas, r `elem` [WingA, WingB]]
      held = S.union core tips
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples moved), S.member i held]
  faces <- checked (frameFaces (surfaceFrame sheet))
  let normals = M.fromList [(faceId f, v3z (polygonNormal (faceCorners f))) | f <- faces]
  orders <- traverse (directed normals) (faceOrders (surfaceFrame sheet))
  unless (componentCount moved == 1 && length (triangles moved) == 448 && length (samples moved) == 237) (bad "unexpected whole-crane material mesh")
  let fixture = CraneSpread sheet refined moved pins core (S.fromList (M.keys (pocketRegions atlas))) hinges orders tips
  pure (WholeCrane fixture atlas core marks (IM.size anchors))
  where
    analytic p = let V3 x y z = position p; V2 u v = sampleMaterial p; angle = pi / 18 in V3 x ((1 - sqrt 2 / 2) + (y - (1 - sqrt 2 / 2)) * cos angle) (z - (v - u) / sqrt 2 * sin angle)

-- | One pose the gallery draws: the stem of its files, its title, how its
-- positions were made, and its mesh. The gallery's one diagnostic, a refused
-- solve, is not a 'CranePose': nothing here says how to make it.
data CranePose = CranePose
  { craneStem :: !String,
    craneTitle :: !Text,
    craneConstruction :: !Construction,
    craneMesh :: !MaterialMesh
  }

-- | How a pose's positions are made. Its geometry level follows from this,
-- and so does whether the same pose can be made again on a finer mesh.
data Construction
  = -- | The rigidly folded sheet: the closed crane.
    FoldedSheet
  | -- | The first candidate, placed around the saved body. The saved body
    -- exists only at the study's own resolution, so this pose cannot be
    -- made again on a finer mesh.
    PlacedAroundBody
  | -- | 'placePillow' with a body width across the wings and a wing tangent
    -- at the body rim.
    PlacedPillow !Double !Double
  deriving stock (Eq, Show)

-- | Where a pose's positions came from, for its fidelity record.
craneGeometry :: CranePose -> Geometry
craneGeometry pose = case craneConstruction pose of
  FoldedSheet -> RigidPanels
  PlacedAroundBody -> AsPrescribed
  PlacedPillow _ _ -> AsPrescribed

-- | The wing spreads the gallery offers: a percentage, the stem of that
-- pose's files, and its title. At 50% the spread is the narrower body's own,
-- so the 50% setting reuses the @narrow@ pose, its stem and its title, rather
-- than drawing the same mesh again under a second name.
wholeCraneOpenings :: [(Int, String, Text)]
wholeCraneOpenings = [(0, "spread-0", "More tucked"), (25, "spread-25", "Slightly tucked"), (50, "narrow", "Middle spread"), (75, "spread-75", "Slightly wider"), (100, "spread-100", "More spread")]

-- | Every pose the gallery draws, in its order. The closed crane is the
-- rigidly folded sheet, cut into the mesh's triangles; every other pose was
-- placed.
wholeCranePoses :: WholeCrane -> Either SpreadError [CranePose]
wholeCranePoses study = mapM (\(stem, title, construction) -> CranePose stem title construction <$> made study construction) cranePoseTable

-- | One of the gallery's poses, by the stem of its files.
cranePose :: WholeCrane -> String -> Either SpreadError CranePose
cranePose study stem = case [(title, construction) | (name, title, construction) <- cranePoseTable, name == stem] of
  [(title, construction)] -> CranePose stem title construction <$> made study construction
  _ -> bad ("the whole-crane gallery draws no pose " <> T.pack stem)

-- | The gallery's poses: the stem of each one's files, its title, and how
-- it is made.
cranePoseTable :: [(String, Text, Construction)]
cranePoseTable =
  [ ("before", "Closed crane", FoldedSheet),
    ("after", "Opened crane · prescribed static candidate", PlacedAroundBody),
    ("pillow", "Pillow body · visual target", pillowShape),
    ("compact", "Less spread · visual target", compactShape),
    ("narrow", "Narrower body · visual target", narrowShape)
  ]
    ++ [(name, title <> " · visual target", PlacedPillow 0.5 (spreadAngle (fromIntegral percent / 100))) | (percent, name, title) <- wholeCraneOpenings, percent /= 50]

-- | A pose's mesh at the study's own resolution.
made :: WholeCrane -> Construction -> Either SpreadError MaterialMesh
made study = \case
  FoldedSheet -> Right (refinedMesh (spreadRefined (wholeSpread study)))
  PlacedAroundBody -> Right (spreadMesh (wholeSpread study))
  PlacedPillow bodyWidthScale start -> pillowCraneWith bodyWidthScale start study

-- | A pose made again on another refinement of the sheet, or nothing when it
-- cannot be: the same construction, sampled more or less finely.
remadeOn :: WholeCrane -> RefinedSurface -> Construction -> Either SpreadError (Maybe MaterialMesh)
remadeOn study refined = \case
  FoldedSheet -> Right (Just (refinedMesh refined))
  PlacedAroundBody -> Right Nothing
  PlacedPillow bodyWidthScale start -> Just <$> placePillow (wholeMap study) refined bodyWidthScale start

-- | What a pose's drawings and cards add to its name so that it is not taken
-- for paper: "shape sketch" when it was placed rather than folded. Every
-- level is matched by name, so a level added later is a warning here until
-- someone decides what it should say.
craneCaveat :: CranePose -> Maybe Text
craneCaveat pose = case craneGeometry pose of
  AsPrescribed -> Just "shape sketch"
  RigidPanels -> Nothing

-- | Text shown with a pose, such as its title or the title of one of its
-- drawings, followed by the pose's caveat when it has one:
-- "Crane upright · three-quarter · shape sketch".
withCaveat :: CranePose -> Text -> Text
withCaveat pose text = maybe text (\caveat -> text <> " · " <> caveat) (craneCaveat pose)

-- Material triangles are non-overlapping on the original square, even when
-- their folded positions coincide. Barycentric weights locate the same piece
-- of paper, including a boundary vertex shared by several triangles.
interpolateMaterial :: V2 -> [MaterialSample] -> Maybe V3
interpolateMaterial p [a, b, c]
  | abs denominator < 1e-15 = Nothing
  | minimum [u, v, w] < -1e-9 = Nothing
  | otherwise = Just (u *^ position a ^+^ v *^ position b ^+^ w *^ position c)
  where
    ab = sampleMaterial b ^-^ sampleMaterial a
    ac = sampleMaterial c ^-^ sampleMaterial a
    ap = p ^-^ sampleMaterial a
    denominator = cross2 ab ac
    v = cross2 ap ac / denominator
    w = cross2 ab ap / denominator
    u = 1 - v - w
interpolateMaterial _ _ = Nothing

type Fit = (V3, V3, V3, V3)

-- | A second static shape proposal, with the body released from the saved
-- ten-degree specimen. In this fixture negative Y is UP: X runs from head to
-- tail and Z separates the wings. The original central material is spread
-- over a shallow cushion, and the four attached sectors follow its rim.
-- This is authored geometry, not a pressure or material solve. In particular
-- the graph continuation may strain the collars; retain their diagnostics.
pillowCrane :: WholeCrane -> Either SpreadError MaterialMesh
pillowCrane study = made study pillowShape

pillowShape :: Construction
pillowShape = PlacedPillow 1 (-(pi / 12))

-- | A less spread visual target: narrow the cushion across the wings by 25%
-- and raise each wing arch by 35 degrees. The arch keeps its length and turn;
-- reducing its horizontal reach does not shorten the wing or scale a drawing.
-- This is another static construction, not a motion from the wider target.
compactPillowCrane :: WholeCrane -> Either SpreadError MaterialMesh
compactPillowCrane study = made study compactShape

compactShape :: Construction
compactShape = PlacedPillow 0.75 (-(5 * pi / 18))

-- | Narrow only the previous target's body by another third. Its height and
-- head-to-tail extent stay fixed; the same raised wing arches move inward
-- with their roots. This isolates body width from a change of wing angle.
narrowPillowCrane :: WholeCrane -> Either SpreadError MaterialMesh
narrowPillowCrane study = made study narrowShape

narrowShape :: Construction
narrowShape = PlacedPillow 0.5 (-(5 * pi / 18))

-- | An authored wing-spread control on the same narrow cushion. Zero holds
-- the wings higher (a -70-degree root tangent); one lowers them outward
-- (-30 degrees). Neither endpoint is the closed crane or a physical limit.
-- The midpoint reproduces 'narrowPillowCrane'. Each setting constructs new
-- anchors and continues their displacement, rather than interpolating meshes.
-- This changes the silhouette, not the status of these invalid paper shapes.
pillowCraneAtSpread :: Double -> WholeCrane -> Either SpreadError MaterialMesh
pillowCraneAtSpread amount study = do
  unless (amount >= 0 && amount <= 1) (bad "pillow wing spread must be finite and between zero and one")
  made study (PlacedPillow 0.5 (spreadAngle amount))

-- | The wing tangent at the body rim for a spread setting between zero and
-- one: -70 degrees at zero, -30 at one.
spreadAngle :: Double -> Double
spreadAngle amount = -(5 * pi / 18) + (amount - 0.5) * (2 * pi / 9)

-- | How many times the study refines the sheet: its mesh has 448 triangles.
studyLevel :: Int
studyLevel = 1

-- | The sheet refined @levels@ times, with a hinge on every interior edge:
-- each crease folded as in the closed crane, every other edge a panel bend.
-- One level is the study's mesh, 448 triangles; each level more splits every
-- triangle into four.
refinedCrane :: Int -> PocketMap -> Either SpreadError (RefinedSurface, [Hinge])
refinedCrane levels atlas = do
  let sheet = pocketSurface atlas
  features <- checked (surfaceFeatures sheet)
  let targets = M.fromList [(creaseId c, if creaseAssignment c == Mountain then -pi else if creaseAssignment c == Valley then pi else 0) | (c, _) <- features, creaseAssignment c `notElem` [Border, Cut]]
  checked (buildSurfaceHinges (Bending 1 0.2) levels sheet targets)

-- The first parameter changes only the body's width across the wings. The
-- second is the wing tangent angle at the body rim; negative angles point up
-- because this fixture's negative Y is up. All pillow targets use a 30-degree arch.
pillowCraneWith :: Double -> Double -> WholeCrane -> Either SpreadError MaterialMesh
pillowCraneWith bodyWidthScale start study = do
  let fixture = wholeSpread study
  moved <- placePillow (wholeMap study) (spreadRefined fixture) bodyWidthScale start
  _ <- spreadSurface fixture moved
  pure moved

-- | The pillow construction on the sheet at any refinement: cushion anchors
-- on the body core, arch anchors on the outer wing strips, and a smoothed
-- fill of everything else. It reads only the mesh and the pocket map, so the
-- same pose can be placed on a finer mesh.
placePillow :: PocketMap -> RefinedSurface -> Double -> Double -> Either SpreadError MaterialMesh
placePillow atlas refined bodyWidthScale start = do
  let base = refinedMesh refined
      tagged = zip (triangles base) (refinedPanels refined)
      original = IM.fromList (zip [0 ..] (samples base))
      memberships = IM.fromListWith S.union [(i, S.singleton r) | (tri, owner) <- tagged, Just r <- [M.lookup owner (pocketRegions atlas)], i <- vertices tri]
      core = S.fromList [i | (tri, owner) <- tagged, owner `elem` regionFaces atlas BodyCore, i <- vertices tri]
      radius = (sqrt 2 - 1) / 2
      cushion p =
        let V2 u v = sampleMaterial p
            x = (1 - u - v) / sqrt 2
            z = (u - v) / sqrt 2
            dome = max 0 (1 - (x / radius) ^ (2 :: Int)) * max 0 (1 - (z / radius) ^ (2 :: Int))
         in V3 (1 + x) (0.44 - 0.045 * dome) (bodyWidthScale * z)
      anchors = IM.map cushion (IM.filterWithKey (\i _ -> S.member i core) original)
  -- Spread the outer wing strips as shallow circular arches. Holding entire
  -- strips, rather than only two tips, names the intended wing orientation.
  let wingTarget i p = case S.toList (IM.findWithDefault S.empty i memberships) of
        [r]
          | r `elem` [WingA, WingB],
            v3y (position p) <= 0.25 + 1e-9 ->
              let V3 x y _ = position p
                  len = 0.5 - y
                  turn = (pi / 6) / 0.5
                  angle = start + turn * len
                  side = if r == WingA then -1 else 1
               in Just (V3 x (0.44 + (cos start - cos angle) / turn) (side * (bodyWidthScale * radius + (sin angle - sin start) / turn)))
        _ -> Nothing
      wingAnchors = IM.mapMaybeWithKey wingTarget original
      targets = IM.union anchors wingAnchors
      restDistance a b = case (IM.lookup a original, IM.lookup b original) of
        (Just p, Just q) -> norm (sampleMaterial p ^-^ sampleMaterial q)
        _ -> 0
  unless (all (\(a, b) -> restDistance a b > 0) (meshEdges base)) (bad "pillow continuation needs positive material edge lengths")
  -- A uniform graph weight can put most displacement across a tiny material
  -- edge. Penalise relative displacement instead. This smooths an authored
  -- guess; it still cannot enforce paper lengths or contact.
  continued <- continueDisplacementsWith (\a b -> 1 / restDistance a b) base (IM.map position original) targets
  pure base {samples = [p {position = IM.findWithDefault (position p) i continued} | (i, p) <- IM.toList original]}

-- Least-squares plane tangents, made perpendicular and unit length so the
-- continuation itself is rigid. It cannot satisfy every deformed attachment;
-- the graph correction below carries those residuals into the remaining sheet.
fitWing :: IM.IntMap (S.Set Region) -> IM.IntMap MaterialSample -> IM.IntMap V3 -> Region -> Either SpreadError Fit
fitWing memberships original anchors region = do
  let pairs = [(position p, q) | (i, q) <- IM.toList anchors, S.member region (IM.findWithDefault S.empty i memberships), Just p <- [IM.lookup i original]]
  unless (length pairs >= 3) (bad "wing fit has fewer than three attachment samples")
  let average ps = (1 / fromIntegral (length ps)) *^ foldl' (^+^) (V3 0 0 0) ps
      from = average (map fst pairs)
      to = average (map snd pairs)
      shifted = [(p ^-^ from, q ^-^ to) | (p, q) <- pairs]
      xx = sum [v3x p * v3x p | (p, _) <- shifted]
      yy = sum [v3y p * v3y p | (p, _) <- shifted]
      xy = sum [v3x p * v3y p | (p, _) <- shifted]
      xq = foldl' (^+^) (V3 0 0 0) [v3x p *^ q | (p, q) <- shifted]
      yq = foldl' (^+^) (V3 0 0 0) [v3y p *^ q | (p, q) <- shifted]
      det = xx * yy - xy * xy
  unless (det > 1e-14) (bad "wing attachment samples do not span a plane")
  ex <- maybe (bad "wing fit has no first tangent") Right (normalize ((1 / det) *^ (yy *^ xq ^-^ xy *^ yq)))
  let ey0 = (1 / det) *^ (xx *^ yq ^-^ xy *^ xq)
  ey <- maybe (bad "wing fit has no second tangent") Right (normalize (ey0 ^-^ dot ex ey0 *^ ex))
  pure (from, to, ex, ey)

applyFit :: Fit -> V3 -> V3
applyFit (from, to, ex, ey) p = let V3 x y z = p ^-^ from in to ^+^ x *^ ex ^+^ y *^ ey ^+^ z *^ cross ex ey

continueDisplacements :: MaterialMesh -> IM.IntMap V3 -> IM.IntMap V3 -> Either SpreadError (IM.IntMap V3)
continueDisplacements = continueDisplacementsWith (\_ _ -> 1)

continueDisplacementsWith :: (Int -> Int -> Double) -> MaterialMesh -> IM.IntMap V3 -> IM.IntMap V3 -> Either SpreadError (IM.IntMap V3)
continueDisplacementsWith weight mesh baseline anchors = do
  let free = IM.keys (IM.difference baseline anchors)
      freeSet = S.fromList free
      edges = meshEdges mesh
      rows = [IM.fromList [(i, weight a b * s) | (i, s) <- [(a, 1), (b, -1)], S.member i freeSet] | (a, b) <- edges]
      residual i = IM.findWithDefault (V3 0 0 0) i anchors ^-^ IM.findWithDefault (V3 0 0 0) i baseline
      rhs = IM.fromListWith (^+^) [(a, (weight a b * weight a b) *^ residual b) | (i, j) <- edges, (a, b) <- [(i, j), (j, i)], S.member a freeSet, IM.member b anchors]
  factor <- maybe (bad "cannot continue the body displacement through the full sheet") Right (factorNormal 1e-12 free rows)
  let solve coordinate = applyFactor factor (IM.map coordinate rhs)
      xs = solve v3x
      ys = solve v3y
      zs = solve v3z
      values = IM.mapWithKey (\i p -> p ^+^ V3 (IM.findWithDefault 0 i xs) (IM.findWithDefault 0 i ys) (IM.findWithDefault 0 i zs)) baseline
  pure (IM.union anchors values)

-- | Drawing-scale shape measurements, not volume or air pressure. The body
-- depth is its world-Z range; the paired wing tips report their separation.
wholeMeasurements :: WholeCrane -> MaterialMesh -> Either SpreadError [(Text, Double)]
wholeMeasurements study mesh = do
  _ <- spreadSurface (wholeSpread study) mesh
  let points = IM.fromList (zip [0 ..] (map position (samples mesh)))
      zs = [v3z p | i <- S.toList (wholeCore study), Just p <- [IM.lookup i points]]
      point name = maybe (bad "missing whole-crane landmark") Right (lookup name (wholeMarks study) >>= (`IM.lookup` points))
  a <- point "wing-a"
  b <- point "wing-b"
  neck <- point "neck-head"
  tailTip <- point "tail"
  let restPoints = IM.fromList (zip [0 ..] (map position (samples (refinedMesh (spreadRefined (wholeSpread study))))))
      original name = maybe (bad "missing original landmark") Right (lookup name (wholeMarks study) >>= (`IM.lookup` restPoints))
  originalNeck <- original "neck-head"
  originalTail <- original "tail"
  pure [("bodyDepth", maximum (0 : zs) - minimum (0 : zs)), ("wingTipSeparation", norm (a ^-^ b)), ("neckTipDisplacement", norm (neck ^-^ originalNeck)), ("tailTipDisplacement", norm (tailTip ^-^ originalTail))]

directed :: M.Map FaceId Double -> FaceOrder -> Either SpreadError (FaceId, FaceId)
directed normals o = do
  z <- maybe (bad "missing ordered source normal") Right (M.lookup (orderRelativeTo o) normals)
  pure (if (orderStacking o == Above) == (z > 0) then (orderRelativeTo o, orderFace o) else (orderFace o, orderRelativeTo o))

vertices :: Triangle -> [Int]
vertices (a, b, c) = [a, b, c]

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)

bad :: Text -> Either SpreadError a
bad = Left . SpreadError
