-- | Check the exported angle poses independently of the motion's certificate.
-- The same examples appear in the gallery, but their material lengths, fixed
-- faces, requested angles and failure witnesses are measured here. So is the
-- sign of a turn towards a side, judged by where its paper goes.
module Senbazuru.Origami.FlapSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.List (nub)
import Data.Text qualified as T
import FlapExample
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), FaceOrder (..), FoldFile (..), Frame (..), Stacking (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import Test.Golden (goldenText)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (choose, forAll)

spec :: Spec
spec = describe "checked flap rotation" $ do
  it "folds the quarter-fold fixture by selecting both segments of each hinge" $ do
    source <- keyFrame <$> (loadFoldFile "examples/quarter-fold.fold" >>= right)
    start <- right (foldFrameWith source {edgesFoldAngle = replicate 12 0})
    firstTurn <- right (prepareFlapAlong [EdgeId 8, EdgeId 10] (FaceId 3) (-180) start >>= checkFlap defaultSweepSettings)
    firstEnd <- right (flapAt firstTurn 1)
    let accepted = surfaceFrame firstEnd
    next <- right (foldFrameWith (foldedPattern start) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted})
    secondTurn <- right (prepareFlapAlong [EdgeId 9, EdgeId 11] (FaceId 1) 180 next >>= checkFlap defaultSweepSettings)
    final <- right (flapAt secondTurn 1)
    edgesFoldAngle (surfaceFrame final) `shouldBe` edgesFoldAngle source
    forM_ [firstTurn, secondTurn] $ \motion -> forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
      pose <- right (flapAt motion t)
      materialError pose `shouldSatisfy` (< 1e-12)

  forM_ [FaceId 0, FaceId 1] $ \side ->
    it ("keeps the opposite face still when moving face " ++ show side) $ do
      start <- right (foldFrameWith singleFlap)
      motion <- right (prepareFlap (EdgeId 6) side 150 start >>= checkFlap defaultSweepSettings)
      flapMovingFaces motion `shouldBe` [side]
      sweepOutcome (flapCheck motion) `shouldBe` SweepClear
      original <- right (surfaceFromFolded start)
      forM_ [0, 0.2 .. 1] $ \t -> do
        current <- right (flapAt motion t)
        let fr = surfaceFrame current
        edgesFoldAngle fr `shouldBe` replicate 6 0 ++ [15 + 150 * t]
        facesVertices fr `shouldBe` facesVertices (surfaceFrame original)
        edgesVertices fr `shouldBe` edgesVertices (surfaceFrame original)
        map sampleMaterial (surfaceSamples current) `shouldBe` map sampleMaterial (surfaceSamples original)
        materialError current `shouldSatisfy` (< 1e-12)
        fixed <- right (surfacePanelSamples original)
        actual <- right (surfacePanelSamples current)
        forM_ [(fid, ps) | (fid, ps) <- fixed, fid /= side] $ \(fid, ps) ->
          case lookup fid actual of
            Just qs -> maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ps qs) `shouldSatisfy` (< 1e-12)
            Nothing -> expectationFailure "fixed face disappeared"
        -- The dihedral angle measured from material-wound panel normals is
        -- independent of the angle list written to the frame.
        faces <- right (frameFaces fr)
        case faces of
          [a, b] -> abs (angleBetween a b - (15 + 150 * t)) `shouldSatisfy` (< 1e-9)
          _ -> expectationFailure "single fold changed face count"

  prop "preserves material lengths for either direction between open angles" $
    forAll (choose (20, 160)) $ \from -> forAll (choose (20, 160)) $ \to ->
      case do
        start <- either (Left . show) Right (foldFrameWith singleFlap {edgesFoldAngle = replicate 6 0 ++ [from]})
        motion <- either (Left . show) Right (prepareFlap (EdgeId 6) (FaceId 1) (to - from) start >>= checkFlap defaultSweepSettings)
        traverse (either (Left . show) Right . flapAt motion) [0, 0.3, 0.7, 1] of
        Left _ -> False
        Right states -> all ((< 1e-12) . materialError) states

  it "preserves material coordinates and decisions at different model scales" $ do
    forM_ [1e-5, 1, 1e5] $ \scale -> do
      start <- right (foldFrameWith singleFlap {verticesCoords = map (map (* scale)) (verticesCoords singleFlap)})
      motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
      state <- right (flapAt motion 0.5)
      maximum (map materialU (surfaceSamples state)) `shouldBe` scale
      materialError state `shouldSatisfy` (< 1e-10)

  it "clears the opposing-flap route and refuses a full turn with the same endpoint" $ do
    start <- right (foldFrameWith opposingFlap)
    good <- right (prepareFlap (EdgeId 9) (FaceId 2) 16 start >>= checkFlap defaultSweepSettings)
    end <- right (flapAt good 1)
    materialError end `shouldSatisfy` (< 1e-12)
    bad <- right (prepareFlap (EdgeId 9) (FaceId 2) 360 start)
    returned <- right (foldFrame opposingFlap {edgesFoldAngle = replicate 8 0 ++ [145, 465]})
    let differences = zipWith (-) (concat (verticesCoords returned)) (concat (verticesCoords (foldedFrame start)))
    differences `shouldSatisfy` all ((< 1e-12) . abs)
    case checkFlap defaultSweepSettings bad of
      Left (FlapCollision t pairs) -> do
        t `shouldSatisfy` (\v -> v > 0 && v < 1)
        pairs `shouldContain` [(FaceId 0, FaceId 2)]
        -- Recreate the reported angle state without the flap implementation
        -- and check the named physical panels intersect at that witness.
        witness <- right (foldFrame opposingFlap {edgesFoldAngle = replicate 8 0 ++ [145, 105 + 360 * t]})
        faces <- right (frameFaces witness)
        report <- right (checkPanelContact (V3 0 0 1) [] [Panel (name (faceId f)) (faceCorners f) | f <- faces])
        crossingPanels report `shouldSatisfy` (not . null)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "unsafe full turn was accepted"

  it "moves all faces beyond the crease, including a previously folded flap" $ do
    start <- right (foldFrameWith opposingFlap)
    motion <- right (prepareFlap (EdgeId 8) (FaceId 1) (-10) start >>= checkFlap defaultSweepSettings)
    flapMovingFaces motion `shouldBe` [FaceId 1, FaceId 2]
    forM_ [0, 0.5, 1] $ \t -> do
      current <- right (flapAt motion t)
      edgesFoldAngle (surfaceFrame current) `shouldBe` replicate 8 0 ++ [145 - 10 * t, 105]
      materialError current `shouldSatisfy` (< 1e-12)

  it "forms a two-layer flap and retains its order throughout lifting and lowering" $ forM_ [touchingFlap, alignedFlap] $ \sheetFixture -> do
    unfolded <- right (foldFrameWith sheetFixture {edgesFoldAngle = replicate 10 0, faceOrders = []})
    forming <- right (prepareFlap (EdgeId 9) (FaceId 2) 180 unfolded >>= checkFlap defaultSweepSettings)
    formed <- right (flapAt forming 1)
    faceOrders (surfaceFrame formed) `shouldBe` faceOrders sheetFixture
    forM_ [(0, 90), (90, 0), (30, 150), (150, 30), (0, -90), (-90, 0)] $ \(from, to) -> do
      start <- right (foldFrameWith sheetFixture {edgesFoldAngle = replicate 8 0 ++ [from, 180]})
      original <- right (surfaceFromFolded start)
      motion <- right (prepareFlap (EdgeId 8) (FaceId 1) (to - from) start >>= checkFlap defaultSweepSettings)
      flapMovingFaces motion `shouldBe` [FaceId 1, FaceId 2]
      forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
        current <- right (flapAt motion t)
        let fr = surfaceFrame current
        edgesFoldAngle fr `shouldBe` replicate 8 0 ++ [from + t * (to - from), 180]
        faceOrders fr `shouldBe` faceOrders sheetFixture
        map sampleMaterial (surfaceSamples current) `shouldBe` map sampleMaterial (surfaceSamples original)
        facesVertices fr `shouldBe` facesVertices (surfaceFrame original)
        length (surfaceSamples current) `shouldBe` 8
        materialError current `shouldSatisfy` (< 1e-12)
        initialPanels <- right (surfacePanelSamples original)
        currentPanels <- right (surfacePanelSamples current)
        case (lookup (FaceId 0) initialPanels, lookup (FaceId 0) currentPanels) of
          (Just ps, Just qs) -> maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ps qs) `shouldSatisfy` (< 1e-12)
          _ -> expectationFailure "stationary panel disappeared"
        faces <- right (frameFaces fr)
        case faces of
          [_, middle, top] -> do
            let a = polygonNormal (faceCorners middle)
                b = polygonNormal (faceCorners top)
            norm ((1 / norm a) *^ a ^+^ (1 / norm b) *^ b) `shouldSatisfy` (< 1e-12)
            -- Select the measuring direction from the actual middle panel,
            -- independently of the checker's order/triangle bookkeeping.
            let panelNormal = polygonNormal (faceCorners middle)
            report <- right (checkPanelContact panelNormal [("1", "2")] [Panel (name (faceId f)) (faceCorners f) | f <- faces])
            contactPassed report `shouldBe` True
          _ -> expectationFailure "stack changed panel count"

  it "lifts a full-width stack with an unjoined edge along the hinge" $ do
    start <- right (foldFrameWith alignedFlap)
    motion <- right (prepareFlap (EdgeId 8) (FaceId 1) 90 start >>= checkFlap defaultSweepSettings)
    sweepOutcome (flapCheck motion) `shouldBe` SweepClear
    forM_ [0, 0.1 .. 1] $ \t -> do
      state <- right (flapAt motion t)
      let vertices = zip [0 :: Int ..] (surfaceSamples state)
      -- Upper free corners coincide with the lower hinge, but their original
      -- positions and ids must not be merged. The mesh still has eight samples.
      length vertices `shouldBe` 8
      forM_ [(1, 3), (6, 4)] $ \(a, b) -> case (lookup a vertices, lookup b vertices) of
        (Just p, Just q) -> do
          norm (position p ^-^ position q) `shouldSatisfy` (< 1e-12)
          norm (sampleMaterial p ^-^ sampleMaterial q) `shouldSatisfy` (> 0.6)
        _ -> expectationFailure "hinge corner disappeared"
      faces <- right (frameFaces (surfaceFrame state))
      case faces of
        [fixed, middle, _] -> abs (angleBetween fixed middle - 90 * t) `shouldSatisfy` (< 1e-6)
        _ -> expectationFailure "full-width stack changed panels"

  it "does not widen the hinge rule to an upper layer extending across the crease" $ do
    let overhanging = alignedFlap {verticesCoords = [[0, 0], [1 / 3, 0], [2 / 3, 0], [1.01, 0], [1.01, 1], [2 / 3, 1], [1 / 3, 1], [0, 1]]}
    start <- right (foldFrameWith overhanging)
    motion <- right (prepareFlap (EdgeId 8) (FaceId 1) 90 start)
    checkFlap defaultSweepSettings motion `shouldSatisfy` isLeft

  it "keeps the stack stationary when the opposite side is selected" $ forM_ [touchingFlap, alignedFlap] $ \sheetFixture -> do
    start <- right (foldFrameWith sheetFixture)
    original <- right (surfaceFromFolded start >>= surfacePanelSamples)
    motion <- right (prepareFlap (EdgeId 8) (FaceId 0) 90 start >>= checkFlap defaultSweepSettings)
    flapMovingFaces motion `shouldBe` [FaceId 0]
    forM_ [0, 0.5, 1] $ \t -> do
      current <- right (flapAt motion t)
      faceOrders (surfaceFrame current) `shouldBe` faceOrders sheetFixture
      panels <- right (surfacePanelSamples current)
      forM_ [FaceId 1, FaceId 2] $ \fid -> case (lookup fid original, lookup fid panels) of
        (Just ps, Just qs) -> maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ps qs) `shouldSatisfy` (< 1e-12)
        _ -> expectationFailure "stationary stack disappeared"

  it "combines the stack's retained order with flat landing and departure orders" $ forM_ [touchingFlap, alignedFlap] $ \sheetFixture -> do
    start <- right (foldFrameWith sheetFixture)
    closing <- right (prepareFlap (EdgeId 8) (FaceId 1) 180 start >>= checkFlap defaultSweepSettings)
    closed <- right (flapAt closing 1)
    let landed = surfaceFrame closed
    faceOrders landed `shouldMatchList` [FaceOrder (FaceId 2) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 0) Above, FaceOrder (FaceId 2) (FaceId 0) Above]
    rest <- right (foldFrameWith sheetFixture {edgesFoldAngle = edgesFoldAngle landed, faceOrders = faceOrders landed})
    opening <- right (prepareFlap (EdgeId 8) (FaceId 1) (-180) rest >>= checkFlap defaultSweepSettings)
    open <- right (flapAt opening 1)
    faceOrders (surfaceFrame open) `shouldBe` faceOrders sheetFixture
    wrong <- right (prepareFlap (EdgeId 8) (FaceId 1) 180 rest)
    case checkFlap defaultSweepSettings wrong of
      Left FlapEndpointOrder {} -> pure ()
      other -> expectationFailure (show other)

  it "refuses a stack without orders or with contradictory orders even when upright" $ forM_ [touchingFlap, alignedFlap] $ \sheetFixture -> do
    forM_ [0, 90] $ \angle -> do
      let sheet = sheetFixture {edgesFoldAngle = replicate 8 0 ++ [angle, 180]}
      missing <- right (foldFrameWith sheet {faceOrders = []})
      motion <- right (prepareFlap (EdgeId 8) (FaceId 1) 15 missing)
      checkFlap defaultSweepSettings motion `shouldSatisfy` isLeft
      conflict <- right (foldFrameWith sheet {faceOrders = [FaceOrder (FaceId 2) (FaceId 1) Above, FaceOrder (FaceId 2) (FaceId 1) Below]})
      case prepareFlap (EdgeId 8) (FaceId 1) 15 conflict of
        Left err@FlapStackOrder {} -> explain err `shouldSatisfy` (not . T.null)
        other -> expectationFailure (show other)

  it "preserves stack orders under winding changes, reverse notation and model scale" $ forM_ [touchingFlap, alignedFlap] $ \sheetFixture -> do
    forM_ [1e-5, 1, 1e5] $ \scale -> forM_ [False, True] $ \backwards -> do
      let sheet =
            sheetFixture
              { verticesCoords = map (map (* scale)) (verticesCoords sheetFixture),
                facesVertices = (if backwards then map reverse else id) (facesVertices sheetFixture),
                faceOrders = [FaceOrder (FaceId 1) (FaceId 2) (if backwards then Below else Above)]
              }
      start <- right (foldFrameWith sheet)
      motion <- right (prepareFlap (EdgeId 8) (FaceId 1) 90 start >>= checkFlap defaultSweepSettings)
      forM_ [0, 0.5, 1] $ \t -> do
        current <- right (flapAt motion t)
        faceOrders (surfaceFrame current) `shouldBe` faceOrders (foldedFrame start)
        materialError current `shouldSatisfy` (< 1e-10)

  it "does not let a permitted moving stack hide a collision with another flap" $ do
    start <- right (foldFrameWith blockedStack)
    safe <- right (prepareFlap (EdgeId 11) (FaceId 2) 16 start >>= checkFlap defaultSweepSettings)
    flapMovingFaces safe `shouldBe` [FaceId 2, FaceId 3]
    unsafe <- right (prepareFlap (EdgeId 11) (FaceId 2) 360 start)
    case checkFlap defaultSweepSettings unsafe of
      Left (FlapCollision t pairs) -> do
        t `shouldSatisfy` (\value -> value > 0 && value < 1)
        pairs `shouldContain` [(FaceId 0, FaceId 2)]
        witness <- right (foldFrame blockedStack {edgesFoldAngle = replicate 10 0 ++ [145, 105 + 360 * t, 180]})
        faces <- right (frameFaces witness)
        report <- right (checkPanelContact (V3 0 0 1) [] [Panel (name (faceId f)) (faceCorners f) | f <- faces])
        crossingPanels report `shouldContain` [("0", "2")]
      other -> expectationFailure (show other)

  it "retains three contacting layers and refuses a cycle across their orders" $ do
    let sheet =
          blockedStack
            { verticesCoords = [[0, 0], [0.25, 0], [0.5, 0], [0.75, 0], [1, 0], [1, 1], [0.75, 1], [0.5, 1], [0.25, 1], [0, 1]],
              edgesFoldAngle = replicate 10 0 ++ [0, 180, 180],
              faceOrders = [FaceOrder (FaceId 2) (FaceId 1) Above, FaceOrder (FaceId 3) (FaceId 1) Above, FaceOrder (FaceId 2) (FaceId 3) Above]
            }
    start <- right (foldFrameWith sheet)
    motion <- right (prepareFlap (EdgeId 10) (FaceId 1) 90 start >>= checkFlap defaultSweepSettings)
    flapMovingFaces motion `shouldBe` map FaceId [1, 2, 3]
    forM_ [0, 0.5, 1] $ \t -> do
      state <- right (flapAt motion t)
      faceOrders (surfaceFrame state) `shouldBe` faceOrders sheet
      materialError state `shouldSatisfy` (< 1e-12)
    cyclic <- right (foldFrameWith sheet {faceOrders = [FaceOrder (FaceId 2) (FaceId 1) Above, FaceOrder (FaceId 3) (FaceId 2) Below, FaceOrder (FaceId 1) (FaceId 3) Above]})
    case prepareFlap (EdgeId 10) (FaceId 1) 90 cyclic of
      Left FlapStackOrder {} -> pure ()
      other -> expectationFailure (show other)

  it "uses the folded winding when the original face rings and crease direction are reversed" $ do
    start <- right (foldFrameWith singleFlap {facesVertices = map reverse (facesVertices singleFlap), edgesVertices = [(b, a) | (a, b) <- edgesVertices singleFlap]})
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    state <- right (flapAt motion 0.5)
    materialError state `shouldSatisfy` (< 1e-12)
    faces <- right (frameFaces (surfaceFrame state))
    case faces of
      [a, b] -> abs (angleBetween a b - 90) `shouldSatisfy` (< 1e-9)
      _ -> expectationFailure "single fold changed face count"

  it "renders a reviewed SVG step page from checked angle states" $ do
    start <- right (foldFrameWith singleFlap)
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    states <- right (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
    basis <- maybe (fail "invalid camera") pure (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
    page <- right (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (map materialFrame states))
    diagram <- maybe (fail "no checked states to draw") pure page
    goldenText "test/golden/checked-flap.svg" (renderSvg defaultPage {pageWidth = 1120, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Single fold"} diagram)

  it "refuses unresolved work without supplying exportable poses" $ do
    start <- right (foldFrameWith opposingFlap)
    motion <- right (prepareFlap (EdgeId 9) (FaceId 2) 360 start)
    case checkFlap (SweepSettings 0 1) motion of
      Left (FlapUnresolved lo hi pairs) -> do
        lo `shouldBe` 0
        hi `shouldBe` 1
        pairs `shouldSatisfy` (not . null)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "exhausted motion was accepted"

  it "renders a reviewed SVG page including the checked flat endpoint" $ do
    start <- right (foldFrameWith (singleAt 0))
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 180 start >>= checkFlap defaultSweepSettings)
    states <- right (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
    basis <- maybe (fail "invalid camera") pure (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
    page <- right (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (map materialFrame states))
    diagram <- maybe (fail "no endpoint states to draw") pure page
    goldenText "test/golden/checked-flat-flap.svg" (renderSvg defaultPage {pageWidth = 1120, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Fold completely flat"} diagram)

  forM_ [("touching stack", touchingFlap, "test/golden/checked-stack-flap.svg"), ("aligned stack", alignedFlap, "test/golden/checked-aligned-stack.svg")] $ \(stackName, sheetFixture, golden) ->
    it ("renders a reviewed SVG sequence of the " ++ stackName ++ " lifting") $ do
      start <- right (foldFrameWith sheetFixture)
      motion <- right (prepareFlap (EdgeId 8) (FaceId 1) 90 start >>= checkFlap defaultSweepSettings)
      states <- right (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
      basis <- maybe (fail "invalid camera") pure (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
      page <- right (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (map materialFrame states))
      diagram <- maybe (fail "no stack states to draw") pure page
      goldenText golden (renderSvg defaultPage {pageWidth = 1120, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Lift both layers together"} diagram)

  it "refuses the quarter fold's coupled crease without tearing a graph loop" $ do
    file <- loadFoldFile "examples/quarter-fold.fold" >>= right
    let fr = keyFrame file
    start <- right (foldFrameWith fr {edgesFoldAngle = replicate (length (edgesVertices fr)) 0})
    -- Each interior crease in this cross has an alternate route around the
    -- centre. The specific face numbering comes from the returned cut pattern.
    faces <- right (frameFaces (foldedPattern start))
    let owners a b = [faceId f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f]
        interior = [(EdgeId i, side) | (i, (a, b)) <- zip [0 ..] (edgesVertices (foldedPattern start)), [side, _] <- [owners a b]]
    interior `shouldSatisfy` (not . null)
    forM_ interior $ \(eid, side) -> case prepareFlap eid side 15 start of
      Left err@(FlapCoupled actual vertices) -> do
        actual `shouldBe` eid
        vertices `shouldSatisfy` (not . null)
        explain err `shouldSatisfy` (not . null . show)
      Left err -> expectationFailure (show err)
      Right _ -> expectationFailure "coupled crease treated as an isolated hinge"

  it "refuses invalid selection, forged starts, nonfinite travel and invalid progress" $ do
    start <- right (foldFrameWith singleFlap)
    prepareFlap (EdgeId 999) (FaceId 1) 10 start `shouldSatisfy` isLeft
    prepareFlap (EdgeId 0) (FaceId 0) 10 start `shouldSatisfy` isLeft
    prepareFlap (EdgeId 6) (FaceId 999) 10 start `shouldSatisfy` isLeft
    forM_ [0 / 0, 1 / 0, 361] $ \angle -> prepareFlap (EdgeId 6) (FaceId 1) angle start `shouldSatisfy` isLeft
    let wrong = (foldedFrame start) {verticesCoords = map (map (* 2)) (verticesCoords (foldedFrame start))}
    prepareFlap (EdgeId 6) (FaceId 1) 10 start {foldedFrame = wrong} `shouldSatisfy` isLeft
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 10 start >>= checkFlap defaultSweepSettings)
    forM_ [0 / 0, -0.1, 1.1] $ \t -> flapAt motion t `shouldSatisfy` isLeft

  it "closes completely and reopens with either moving side and either angle sign" $ do
    forM_ [FaceId 0, FaceId 1] $ \side -> forM_ [-1, 1] $ \sign -> do
      start <- right (foldFrameWith (singleAt 0))
      closing <- right (prepareFlap (EdgeId 6) side (sign * 180) start >>= checkFlap defaultSweepSettings)
      let fixed = if side == FaceId 0 then FaceId 1 else FaceId 0
          expectedOrder = FaceOrder side fixed (if sign > 0 then Above else Below)
      forM_ [0, 1e-6, 1 / 3, 2 / 3, 1 - 1e-6, 1] $ \t -> do
        current <- right (flapAt closing t)
        materialError current `shouldSatisfy` (< 1e-12)
        length (surfaceSamples current) `shouldBe` 6
        edgesFoldAngle (surfaceFrame current) `shouldBe` replicate 6 0 ++ [sign * 180 * t]
        faceOrders (surfaceFrame current) `shouldBe` [expectedOrder | t == 1]
      closed <- right (flapAt closing 1)
      again <- right (foldFrameWith (singleAt (sign * 180)) {faceOrders = faceOrders (surfaceFrame closed)})
      opening <- right (prepareFlap (EdgeId 6) side (negate sign * 180) again >>= checkFlap defaultSweepSettings)
      initially <- right (flapAt opening 0)
      faceOrders (surfaceFrame initially) `shouldBe` [expectedOrder]
      reopened <- right (flapAt opening 1)
      faceOrders (surfaceFrame reopened) `shouldBe` []
      materialError reopened `shouldSatisfy` (< 1e-12)
      faces <- right (frameFaces (surfaceFrame reopened))
      case faces of
        [a, b] -> angleBetween a b `shouldSatisfy` (< 1e-6)
        _ -> expectationFailure "reopening changed panel count"

  it "rejects departure through the declared resting layer, including reversed order notation" $ do
    forM_ [FaceOrder (FaceId 1) (FaceId 0) Above, FaceOrder (FaceId 0) (FaceId 1) Above] $ \order -> do
      start <- right (foldFrameWith (singleAt 180) {faceOrders = [order]})
      wrong <- right (prepareFlap (EdgeId 6) (FaceId 1) 180 start)
      case checkFlap defaultSweepSettings wrong of
        Left FlapEndpointOrder {} -> pure ()
        other -> expectationFailure (show other)
      good <- right (prepareFlap (EdgeId 6) (FaceId 1) (-180) start >>= checkFlap defaultSweepSettings)
      firstPose <- right (flapAt good 0)
      faceOrders (surfaceFrame firstPose) `shouldBe` [FaceOrder (FaceId 1) (FaceId 0) Above]

  it "does not accept a small overshoot or a full turn as endpoint touching" $ do
    forM_ [(0, 180.000001), (15, 165.000001), (0, 360), (0, -180.000001)] $ \(from, travel) -> do
      start <- right (foldFrameWith (singleAt from))
      motion <- right (prepareFlap (EdgeId 6) (FaceId 1) travel start)
      checkFlap defaultSweepSettings motion `shouldSatisfy` isLeft

  it "handles partial approaches to flat endpoints and scaled, reversed material winding" $ do
    forM_ [1e-5, 1, 1e5] $ \scale -> forM_ [(15, 180), (-15, -180), (15, 0), (180, 15)] $ \(from, to) -> do
      let sheet = (singleAt from) {verticesCoords = map (map (* scale)) (verticesCoords singleFlap), facesVertices = map reverse (facesVertices singleFlap)}
      start <- right (foldFrameWith sheet)
      motion <- right (prepareFlap (EdgeId 6) (FaceId 1) (to - from) start >>= checkFlap defaultSweepSettings)
      forM_ [0, 0.5, 1] $ \t -> right (flapAt motion t) >>= (\surface -> materialError surface `shouldSatisfy` (< 1e-10))

  it "does not authorize persistent coplanar layers elsewhere in the sheet" $ do
    start <- right (foldFrameWith opposingFlap {edgesFoldAngle = replicate 8 0 ++ [180, 15]})
    motion <- right (prepareFlap (EdgeId 9) (FaceId 2) 15 start)
    checkFlap defaultSweepSettings motion `shouldSatisfy` isLeft

  it "accepts explicit angles when FOLD leaves assignments unspecified" $ do
    start <- right (foldFrameWith singleFlap {edgesAssignment = []})
    motion <- right (prepareFlap (EdgeId 6) (FaceId 1) 150 start >>= checkFlap defaultSweepSettings)
    state <- right (flapAt motion 1)
    materialError state `shouldSatisfy` (< 1e-12)

  -- On the quarter fold after its first step, the hinge along y = 1/2 is
  -- edges 9 and 11. Face 0 beside edge 9 lies top up and face 3 beside edge 11
  -- lies upside down, so one turn has a different sign read against each.
  describe "turning towards a side" $ do
    it "signs the travel by which way up the first stationary face lies" $ do
      folded <- halfFolded
      forM_ [(TowardPlusZ, 180), (TowardMinusZ, -180)] $ \(toward, travel) -> do
        fromNine <- right (prepareFlapAlong [EdgeId 9, EdgeId 11] (FaceId 1) travel folded)
        prepareFlapToward [EdgeId 9, EdgeId 11] (FaceId 1) 180 toward folded `shouldBe` Right fromNine
        fromEleven <- right (prepareFlapAlong [EdgeId 11, EdgeId 9] (FaceId 2) (negate travel) folded)
        prepareFlapToward [EdgeId 11, EdgeId 9] (FaceId 2) 180 toward folded `shouldBe` Right fromEleven

    it "lifts the moving paper towards the side it names, holding the first stationary face" $ do
      folded <- halfFolded
      forM_ [([EdgeId 9, EdgeId 11], FaceId 1, FaceId 0), ([EdgeId 11, EdgeId 9], FaceId 2, FaceId 3)] $ \(hinge, side, held) ->
        forM_ [(TowardPlusZ, 1), (TowardMinusZ, -1)] $ \(toward, sign) -> do
          turn <- right (prepareFlapToward hinge side 180 toward folded >>= checkFlap defaultSweepSettings)
          flapStationaryFace turn `shouldBe` held
          halfway <- right (flapAt turn 0.5)
          points <- right (frameVertices (surfaceFrame halfway))
          -- Vertices 2, 3 and 6 are the moving paper's vertices off the hinge,
          -- each half a unit from it, so a quarter turn puts each half a unit
          -- up or half a unit down.
          let lifted = [z | (i, V3 _ _ z) <- zip [0 :: Int ..] points, i `elem` [2, 3, 6]]
          length lifted `shouldBe` 3
          forM_ lifted $ \z -> abs (z - sign * 0.5) `shouldSatisfy` (< 1e-12)

    it "refuses a side it cannot read, and a size that is not a turn" $ do
      source <- keyFrame <$> (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
      -- Halfway through the first step, faces 2 and 3 hang straight down.
      hanging <- right (foldFrameWith source {edgesFoldAngle = replicate 8 0 ++ [-90, 0, -90, 0]})
      case prepareFlapToward [EdgeId 8, EdgeId 10] (FaceId 0) 90 TowardPlusZ hanging of
        Left (FlapStationaryNotFlat held normal) -> do
          held `shouldBe` FaceId 3
          norm (normal ^-^ V3 (-1) 0 0) `shouldSatisfy` (< 1e-12)
        other -> expectationFailure ("expected FlapStationaryNotFlat, got " ++ either show (const "a motion") other)
      -- Moving the hanging half instead holds face 0, which lies flat, and
      -- turning it towards +z brings the half back up.
      back <- right (prepareFlapAlong [EdgeId 8, EdgeId 10] (FaceId 3) 90 hanging)
      prepareFlapToward [EdgeId 8, EdgeId 10] (FaceId 3) 90 TowardPlusZ hanging `shouldBe` Right back
      forM_ [-90, 360.5, 0 / 0, 1 / 0] $ \size ->
        case prepareFlapToward [EdgeId 8, EdgeId 10] (FaceId 3) size TowardPlusZ hanging of
          Left (FlapInvalidTurn _) -> pure ()
          other -> expectationFailure ("a turn of " ++ show size ++ ": " ++ either show (const "accepted") other)

-- | The quarter fold after its first step, folded here rather than read from
-- the file's second frame, so that it carries the layer order the step left.
halfFolded :: IO Folded
halfFolded = do
  source <- keyFrame <$> (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  start <- right (foldFrameWith source)
  turn <- right (prepareFlapAlong [EdgeId 8, EdgeId 10] (FaceId 3) (-180) start >>= checkFlap defaultSweepSettings)
  end <- surfaceFrame <$> right (flapAt turn 1)
  right (foldFrameWith (foldedPattern start) {edgesFoldAngle = edgesFoldAngle end, faceOrders = faceOrders end})

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    edges = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- edges, Just p <- [lookup a points], Just q <- [lookup b points]]

singleAt :: Double -> Frame
singleAt angle = singleFlap {edgesFoldAngle = replicate 6 0 ++ [angle]}

angleBetween :: Face -> Face -> Double
angleBetween a b = acos (max (-1) (min 1 (dot (normal a) (normal b)))) * 180 / pi
  where
    normal face = case faceCorners face of
      p : q : r : _ -> let n = cross (q ^-^ p) (r ^-^ p) in (1 / norm n) *^ n
      _ -> V3 0 0 0

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
