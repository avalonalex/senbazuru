-- | Where a flap of a flat-folded model turns from: its root. A study for
-- #455. The owner placed the crane wing's hinge at the neck and tail bases by
-- eye, and wants such choices made by a rule the code applies, not by hand
-- model by model.
--
-- The rule: a flap's hinge may crease only the flap's own paper, and its root
-- is the line furthest from its tip where that is still true. Past it, the
-- hinge would also crease paper beside the flap, which would have to move
-- with it: for the crane wing, the neck and the tail. 'Senbazuru.Origami.Flap'
-- alone does not find this line. A crease through paper that stays still is
-- just a flat crease to a rigid model, so the wing still turns about lines
-- well past its root (the wing scan in 'writeFlapRoot' measures that).
--
-- 'findRoot' finds the root from the folded outline. Take the run of paper
-- across the flap at a given distance from its tip. Each end of the run moves
-- continuously along the flap's edge until the line passes a corner where the
-- flap's edge meets the paper beside it, and there the end jumps out into that
-- paper. The two points just before the first jump on each side are the
-- root's ends, so its direction comes from the corners, not from the lines
-- probed. 'turnAbout' then creases the root through every layer, takes the
-- paper still joined to the tip, and checks that it turns.
module FlapRoot (Prepared (..), prepare, Turn (..), turnAbout, Root (..), findRoot, writeFlapRoot) where

import Control.Monad (when)
import Data.Aeson (encode, object, (.=))
import Data.Aeson.Types (Pair)
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as BL
import Data.List (partition, sortOn)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipSegment, distanceOutside)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Flat (Panel (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Stacking (defaultBudget, solveStackingAs)
import Senbazuru.Origami.ThroughLayers (creaseThroughLayers)
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

-- | A pattern folded once, with the flap named by a point of the flat sheet
-- at its tip. The folded tip alone would not say which flap: both crane
-- wings end at the same folded point.
data Prepared = Prepared
  { preparedSource :: !Frame,
    preparedFolded :: !Folded,
    preparedSheet :: !Sheet,
    preparedTipVertex :: !Int,
    preparedTip :: !V2,
    -- | One length for the model: its larger span in the plane, at least 1.
    preparedScale :: !Double
  }

prepare :: Frame -> V2 -> Either Text Prepared
prepare source (V2 cx cy) = do
  -- 'turnAbout' finds its own crease as the unassigned edges, so a pattern
  -- with unassigned creases of its own would have them cut too.
  when (Unassigned `elem` edgesAssignment source) $
    Left "the pattern already has unassigned creases, which the probe's crease could not be told apart from"
  folded <- first explain (foldFrameWith source)
  sheet <- first explain (flatSheet (foldedFrame folded))
  tipVertex <- case [i | (i, c) <- zip [0 :: Int ..] (verticesCoords (foldedPattern folded)), near c] of
    i : _ -> Right i
    [] -> Left "no vertex of the sheet at the named corner"
  points <- first explain (frameVertices (foldedFrame folded))
  tip <- case drop tipVertex points of
    V3 x y _ : _ -> Right (V2 x y)
    [] -> Left "the tip has no folded position"
  let xs = [x | V3 x _ _ <- points]
      ys = [y | V3 _ y _ <- points]
      scale = maximum [1, maximum xs - minimum xs, maximum ys - minimum ys]
  pure (Prepared source folded sheet tipVertex tip scale)
  where
    near c = case c of
      a : b : _ -> abs (a - cx) < 1e-9 && abs (b - cy) < 1e-9
      _ -> False

-- | The run of paper along the line through @centre@ in the unit direction
-- @direction@ that contains @centre@, as offsets from it, or nothing where
-- @centre@ is off the paper. Shadows that overlap or touch, to a hair, are
-- one run.
runThrough :: Sheet -> V2 -> V2 -> Maybe (Double, Double)
runThrough sheet centre direction = around (merge spans)
  where
    at t = centre `plus` scaled t direction
    along p = dotV (p `minus` centre) direction
    hair = sheetHair sheet
    spans = sortOn fst [(min (along u) (along v), max (along u) (along v)) | p <- sheetPanels sheet, Just (u, v) <- [clipSegment (panelRing p) (at (-1e3), at 1e3)]]
    merge ((a, b) : (c, d) : more)
      | c <= b + hair = merge ((a, max b d) : more)
      | otherwise = (a, b) : merge ((c, d) : more)
    merge rest = rest
    around runs = case [r | r@(a, b) <- runs, a <= hair, b >= negate hair] of
      r : _ -> Just r
      [] -> Nothing

-- | What turning about one segment does.
data Turn = Turn
  { -- | How many of the crease's segments are the hinge, with the paper joined
    -- to the tip on exactly one side.
    turnHinge :: !Int,
    -- | How many faces stay joined to the tip once the crease is cut.
    turnFlapFaces :: !Int,
    -- | How far that paper reaches along the segment's direction, measured
    -- from its first end. This is the whole flap's extent, not the crease's:
    -- it passes the crease's ends wherever the flap is wider than at its
    -- root, as the crane wing is at its widest point.
    turnFlapAlong :: !(Double, Double),
    turnLength :: !Double,
    -- | The way it turns and how many faces move, or why neither way does.
    turnResult :: !(Either Text (Double, Int))
  }

-- | Crease from @from@ to @to@ through every layer under it, take the paper
-- still joined to the tip once the crease is cut, and turn it a quarter turn
-- either way, with the model's layers in stacking state @state@. Only the
-- crease's segments with that paper on exactly one side are the hinge; the
-- rest stay flat creases in paper that does not move.
turnAbout :: Prepared -> Int -> (V2, V2) -> Either Text Turn
turnAbout prepared state (from, to) = do
  let source = preparedSource prepared
      material = foldedPattern (preparedFolded prepared)
  creased <- first explain (creaseThroughLayers from to Unassigned source)
  -- Hold still the face, or the part of it, that the uncreased folding held
  -- still, so the model lands where it did. A crease through it is flat, so
  -- either part of a cut one lands in the same place.
  anchor <- case facesVertices material of
    ring : _ -> Right ring
    [] -> Left "the pattern has no faces"
  let flat frame' (VertexId i) = case drop i (verticesCoords frame') of
        (x : y : _) : _ -> V2 x y
        _ -> V2 0 0
      anchorRing = map (flat material) anchor
      within = all (\v -> distanceOutside anchorRing (flat creased v) <= 1e-9)
      (held, others) = partition within (facesVertices creased)
  folded <- case held of
    ring : more -> first explain (foldFrameWith creased {facesVertices = ring : more ++ others})
    [] -> Left "lost the face the folding holds still"
  let frame = foldedFrame folded
      rings = zip [0 :: Int ..] (facesVertices frame)
      key (VertexId u) (VertexId v) = (min u v, max u v)
      ringEdges' ring = zip ring (drop 1 ring ++ take 1 ring)
      cuts = S.fromList [key u v | ((u, v), Unassigned) <- zip (edgesVertices frame) (edgesAssignment frame)]
      sides = M.fromListWith (++) [(key u v, [i]) | (i, ring) <- rings, (u, v) <- ringEdges' ring]
      neighbours i = [j | Just ring <- [lookup i rings], (u, v) <- ringEdges' ring, S.notMember (key u v) cuts, j <- M.findWithDefault [] (key u v) sides, j /= i]
      reach seen [] = seen
      reach seen (i : queue)
        | S.member i seen = reach seen queue
        | otherwise = reach (S.insert i seen) (neighbours i ++ queue)
      flapFaces = reach S.empty [i | (i, ring) <- rings, VertexId (preparedTipVertex prepared) `elem` ring]
      creaseEdges = [(EdgeId e, [i | i <- M.findWithDefault [] (key u v) sides, S.member i flapFaces]) | (e, ((u, v), Unassigned)) <- zip [0 ..] (zip (edgesVertices frame) (edgesAssignment frame))]
      hinge = [e | (e, [_]) <- creaseEdges]
      wraps = [e | (e, [_, _]) <- creaseEdges]
      direction = unit (to `minus` from)
  points <- first explain (frameVertices frame)
  let point (VertexId i) = case drop i points of
        V3 x y _ : _ -> V2 x y
        [] -> from
      offsets = [dotV (point v `minus` from) direction | (i, ring) <- rings, S.member i flapFaces, v <- ring]
  side <- case (hinge, wraps) of
    ([], _) -> Left "the crease does not separate the tip"
    (_, _ : _) -> Left "the tip's paper reaches across the crease"
    (e : _, []) -> case [i | (e', [i]) <- creaseEdges, e' == e] of
      i : _ -> Right (FaceId i)
      [] -> Left "no face beside the hinge"
  orders <- first explain (solveStackingAs defaultBudget [state] frame)
  let start = folded {foldedFrame = frame {faceOrders = orders}}
      turn degrees = prepareFlapAlong hinge side degrees start >>= checkFlap defaultSweepSettings
      result = case (turn 90, turn (-90)) of
        (Right checked, _) -> Right (90, length (flapMovingFaces checked))
        (_, Right checked) -> Right (-90, length (flapMovingFaces checked))
        (Left a, Left b) -> Left (explain a <> " / " <> explain b)
  pure (Turn (length hinge) (S.size flapFaces) (minimum offsets, maximum offsets) (norm (to `minus` from)) result)

-- | A flap's root, found from the folded outline.
data Root = Root
  { -- | The direction the probing lines advance in: from the tip towards the
    -- middle of the folded model.
    rootAxis :: !V2,
    -- | The root's two ends, and how far along the axis each was found.
    rootEnds :: !(V2, V2),
    rootDistances :: !(Double, Double)
  }

-- | Probe lines across the flap, square to the line from its tip to the
-- middle of the model, every 1/400 of the model's span. On each side, bisect
-- each step until the doubles run out to see whether the run's end jumped
-- within it, and stop at the first that did. A continuous edge changes the
-- end by less and less as the step narrows; a jump does not.
--
-- The rule reads the first jump as the flap's edge meeting the paper beside
-- it, and on the crane's wings that is what it is. But the end also jumps
-- where the flap's own outline steps outward, or where a sideways
-- protrusion ends, and this cannot tell those apart. A step in the flap's own
-- paper would put the root nearer the tip than the real one, and the turn
-- check would still pass: the crease stays in the flap's paper either way.
-- It has been tried on one model.
findRoot :: Prepared -> Either Text Root
findRoot prepared = do
  let sheet = preparedSheet prepared
      tip = preparedTip prepared
      scale = preparedScale prepared
  points <- first explain (frameVertices (foldedFrame (preparedFolded prepared)))
  let middle = scaled (1 / fromIntegral (length points)) (foldr plus (V2 0 0) [V2 x y | V3 x y _ <- points])
      axis = unit (middle `minus` tip)
      across = V2 (negate (v2y axis)) (v2x axis)
      run h = runThrough sheet (tip `plus` scaled h axis) across
      steps = [scale * fromIntegral k / 400 | k <- [1 .. 400 :: Int]]
      jump pick a b = go a b (60 :: Int)
        where
          end h = pick <$> run h
          change p q = maybe 0 abs ((-) <$> end q <*> end p)
          go lo hi 0 = if change lo hi > 1e-6 * scale then Just lo else Nothing
          go lo hi n =
            let mid = (lo + hi) / 2
             in if change lo mid >= change mid hi then go lo mid (n - 1) else go mid hi (n - 1)
      firstJump pick = case [h | (a, b) <- zip steps (drop 1 steps), Just _ <- [run a], Just _ <- [run b], Just h <- [jump pick a b]] of
        h : _ -> Right h
        [] -> Left "the flap's edge never meets other paper"
      corner pick h = case run h of
        Just r -> Right (tip `plus` scaled h axis `plus` scaled (pick r) across)
        Nothing -> Left "lost the paper at a root's end"
  lowAt <- firstJump fst
  highAt <- firstJump snd
  low <- corner fst lowAt
  high <- corner snd highAt
  pure (Root axis (low, high) (lowAt, highAt))

-- | For each corner of the crane's sheet, find the flap's root and turn about
-- it; then, for the wing, probe lines square to its axis from its tip inwards.
writeFlapRoot :: FilePath -> IO ()
writeFlapRoot destination = do
  source <- loadFoldFile "examples/crane.fold" >>= either (die . show) (pure . keyFrame)
  let output = destination </> "flap-root"
  createDirectoryIfMissing True output
  roots <- mapM (rootRow source) [V2 0 0, V2 1 0, V2 0 1, V2 1 1]
  wing <- either (die . T.unpack) pure (prepare source (V2 0 1))
  scan <- mapM (scanRow wing) ([0.05, 0.1 .. 0.35] ++ [0.37, 0.3758, 0.376, 0.38, 0.4, 0.42, 0.45])
  BL.writeFile (output </> "checks.json") (encode (object ["roots" .= roots, "wingScan" .= scan]))
  where
    rootRow source (V2 cx cy) = do
      start <- getCPUTime
      let found = do
            prepared <- prepare source (V2 cx cy)
            root <- findRoot prepared
            pure (root, turnAbout prepared 2 (rootEnds root))
      case found of
        Right (root, _) -> putStrLn ("corner " <> show (cx, cy) <> ": " <> describeRoot root)
        Left err -> putStrLn ("corner " <> show (cx, cy) <> ": " <> T.unpack err)
      settled <- either (const (pure ())) (\(_, t) -> putStrLn ("  " <> either T.unpack describeTurn t)) found >> getCPUTime
      let seconds = fromIntegral (settled - start) / 1e12 :: Double
      pure (object (["corner" .= [cx, cy], "cpuSeconds" .= seconds] ++ either (\e -> ["refused" .= e]) (\(root, t) -> rootJson root ++ either (\e -> ["turnRefused" .= e]) turnJson t) found))
    scanRow wing h = do
      let centre = preparedTip wing `plus` scaled h (V2 0 1)
          across = V2 (-1) 0
          row = do
            (lo, hi) <- maybe (Left "the line misses the paper") Right (runThrough (preparedSheet wing) centre across)
            let ends = (centre `plus` scaled lo across, centre `plus` scaled hi across)
            t <- turnAbout wing 2 ends
            pure (ends, t)
      putStrLn ("wing scan " <> show h <> ": " <> either T.unpack (describeTurn . snd) row)
      pure (object (("distance" .= h) : either (\e -> ["refused" .= e]) (\((V2 ax ay, V2 bx by), t) -> ("ends" .= [[ax, ay], [bx, by]]) : turnJson t) row))
    describeRoot root =
      let (V2 ax ay, V2 bx by) = rootEnds root
       in "root from " <> show (ax, ay) <> " to " <> show (bx, by) <> ", found at " <> show (rootDistances root) <> " along " <> show (v2x (rootAxis root), v2y (rootAxis root))
    describeTurn t = "hinge " <> show (turnHinge t) <> ", flap " <> show (turnFlapFaces t) <> " faces reaching " <> show (turnFlapAlong t) <> " along a crease " <> show (turnLength t) <> " long, " <> either (("no turn: " <>) . T.unpack) show (turnResult t)
    rootJson root =
      let (V2 ax ay, V2 bx by) = rootEnds root
          (d1, d2) = rootDistances root
       in ["root" .= [[ax, ay], [bx, by]], "rootDistances" .= [d1, d2], "axis" .= [v2x (rootAxis root), v2y (rootAxis root)]]
    turnJson :: Turn -> [Pair]
    turnJson t =
      ["hingeSegments" .= turnHinge t, "flapFaces" .= turnFlapFaces t, "flapAlong" .= [fst (turnFlapAlong t), snd (turnFlapAlong t)], "creaseLength" .= turnLength t]
        ++ either (\e -> ["turnRefused" .= e]) (\(degrees, moving) -> ["turnDegrees" .= degrees, "movingFaces" .= moving]) (turnResult t)

plus, minus :: V2 -> V2 -> V2
plus (V2 a b) (V2 c d) = V2 (a + c) (b + d)
minus (V2 a b) (V2 c d) = V2 (a - c) (b - d)

scaled :: Double -> V2 -> V2
scaled k (V2 a b) = V2 (k * a) (k * b)

dotV :: V2 -> V2 -> Double
dotV (V2 a b) (V2 c d) = a * c + b * d

norm :: V2 -> Double
norm v = sqrt (dotV v v)

unit :: V2 -> V2
unit v = scaled (1 / norm v) v
