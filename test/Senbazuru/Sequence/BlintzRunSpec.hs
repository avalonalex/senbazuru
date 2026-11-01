-- | The blintz, run as a sequence: the first of the two migrations PRDs\/09 §9
-- plans, and the end of #282. The run was shown equal to the study's
-- hand-written recipe for it (#493): every move's crease angles exactly, its
-- layer orders, every point of paper within 1e-12, and the drawn page byte for
-- byte. The recipe is gone (#503), and what it checked is checked here on the
-- run's own turns. @test/golden/checked-blintz.svg@, drawn from the run, is
-- the guard the comparison was, and @examples\/blintz-sequence.fold@
-- ("Senbazuru.Sequence.WriteSpec") holds every state the run writes,
-- exactly, coordinates and all.
--
-- A turn starts from the paper the run held then. A record keeps that paper's
-- surface, not the fold it came from, so the fold is made again: the sheet's
-- working pattern with the angles and layer orders of the record's surface
-- before the turn ('startOf'). It is the one fold the recipe started each turn
-- from, since the run numbers its faces as the recipe did.
--
-- Built once, by 'runIO' at the top.
module Senbazuru.Sequence.BlintzRunSpec (spec) where

import BlintzGallery (blintzGallery)
import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Surface
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (MoveFailure (..), ResolveProblem (..), SequenceError (..), refusalKindOf)
import Senbazuru.Sequence.Record hiding (PageAxis (..), Sense (..), Turning (..))
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Corner (..), Layers (..), Move (..), Name (..), RefusalKind (..), Sense (..), Sequence)
import SequenceGallery (pageFile, pageStates, pageSvg, turnOf)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz)

spec :: Spec
spec = describe "the blintz, run as a sequence" $ do
  file <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" file) . elaborate
  blintzRun <- runIO (right (runOn blintz))
  let records = runRecords blintzRun
  turns <- runIO (mapM (right . turnOf) records)
  paper <- runIO (workingPattern <$> right (sheetState file))
  starts <- runIO (mapM (right . startOf paper) records)
  states <- runIO (right (pageStates blintzGallery blintzRun))

  -- From the recipe's spec: four half-turns and a reopening, each holding
  -- the central square still, and the angles and order counts it ends at.
  it "folds the four corners behind, then reopens the first, holding the centre still" $ do
    length records `shouldBe` 5
    length states `shouldBe` 11
    map recordStationary records `shouldBe` replicate 5 (FaceId 0)
    map (snd . recordAngles) records
      `shouldBe` map (replicate 8 0 ++) [[-180, 0, 0, 0], [-180, -180, 0, 0], [-180, -180, -180, 0], replicate 4 (-180), [0, -180, -180, -180]]
    map (length . faceOrders . surfaceFrame . recordAfter) records `shouldBe` [1, 2, 3, 4, 3]

  -- From the recipe's spec, on the run's turns: sampled through each turn,
  -- the paper keeps its lengths, every face's copy of a corner meets the
  -- others, the centre stays put, each crease's measured angle is the angle
  -- asked for, and every contact holds.
  forM_ (zip3 [1 :: Int ..] turns starts) $ \(i, turn, start) ->
    it ("keeps lengths, shared corners, signed crease angles and contact throughout move " ++ show i) $ do
      material <- right (frameVertices (foldedPattern start))
      let materialPoints = zip (map VertexId [0 ..]) material
          originalTopology = facesVertices (foldedPattern start)
      forM_ [0, 0.1 .. 1] $ \t -> do
        sheet <- right (flapAt turn t)
        let fr = surfaceFrame sheet
        facesVertices fr `shouldBe` originalTopology
        length (surfaceSamples sheet) `shouldBe` 8
        materialError sheet `shouldSatisfy` (< 1e-12)
        points <- right (frameVertices fr)
        let placed = zip (map VertexId [0 ..]) points
        -- Independently place each face's copy of each vertex. All copies
        -- must meet at the one position exported for that material id.
        folded <- right (foldFrameWith (foldedPattern start) {edgesFoldAngle = edgesFoldAngle fr, faceOrders = faceOrders fr})
        forM_ (zip (map FaceId [0 ..]) originalTopology) $ \(fid, ring) -> do
          transform <- require "face transform" (IM.lookup (unFaceId fid) (foldedPlacements folded))
          forM_ ring $ \vid -> do
            p <- require "material vertex" (lookup vid materialPoints)
            q <- require "placed vertex" (lookup vid placed)
            norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
        faces <- right (frameFaces fr)
        centre' <- require "central face" (lookup (FaceId 0) [(faceId f, f) | f <- faces])
        forM_ (faceVertexIds centre') $ \vid -> do
          p <- require "central material vertex" (lookup vid materialPoints)
          q <- require "central placed vertex" (lookup vid placed)
          norm (p ^-^ q) `shouldSatisfy` (< 1e-12)
        forM_ (zip (map EdgeId [0 ..]) (zip (edgesVertices fr) (edgesFoldAngle fr))) $ \(eid, ((a, b), requested)) ->
          if unEdgeId eid < 8
            then pure ()
            else do
              corner <- require "corner face" (lookup eid (zip (map EdgeId [8 ..]) [FaceId 2, FaceId 3, FaceId 4, FaceId 1]) >>= (\fid -> lookup fid [(faceId f, f) | f <- faces]))
              let oriented = if (a, b) `elem` ringEdges (faceVertexIds centre') then (a, b) else (b, a)
              from <- require "hinge start" (lookup (fst oriented) placed)
              to <- require "hinge end" (lookup (snd oriented) placed)
              let axis = unit (to ^-^ from)
                  fixedNormal = unit (polygonNormal (faceCorners centre'))
                  movingNormal = unit (polygonNormal (faceCorners corner))
                  measured = negate (180 / pi * atan2 (dot axis (cross fixedNormal movingNormal)) (dot fixedNormal movingNormal))
                  difference = measured - requested
              minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-9)
        -- All established contacts are corners below the fixed central
        -- diamond. This direction is independent of the FOLD order encoding.
        let ordered = [(name (orderFace o), "0") | o <- faceOrders fr]
        report <- right (checkPanelContact (V3 0 0 1) ordered [Panel (name (faceId f)) (faceCorners f) | f <- faces])
        contactPassed report `shouldBe` True

  -- From the recipe's spec: each turn starts where the one before it ended.
  it "carries exactly the accepted positions, material ids, angles and orders across each join" $
    forM_ (zip records (drop 1 turns)) $ \(previous, following) -> do
      start <- right (flapAt following 0)
      let end = recordAfter previous
      faceOrders (surfaceFrame start) `shouldMatchList` faceOrders (surfaceFrame end)
      edgesFoldAngle (surfaceFrame start) `shouldBe` edgesFoldAngle (surfaceFrame end)
      map sampleMaterial (surfaceSamples start) `shouldBe` map sampleMaterial (surfaceSamples end)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples start) (surfaceSamples end) `shouldSatisfy` all (< 1e-12)

  -- From the recipe's spec: after the four corners the paper is the fixture's
  -- own folded blintz, its four corners meeting at the centre, all below it.
  it "matches the existing base, with four distinct material corners meeting at its centre" $ do
    completed <- require "completed base" (case drop 3 records of r : _ -> Just (recordAfter r); [] -> Nothing)
    reference <- right (foldFrameWith (keyFrame file))
    centreTransform <- require "reference central transform" (IM.lookup 4 (foldedPlacements reference))
    expected <- map (applyRigid (inverse centreTransform)) <$> right (frameVertices (foldedFrame reference))
    actual <- right (frameVertices (surfaceFrame completed))
    length actual `shouldBe` length expected
    zipWith (\a b -> norm (a ^-^ b)) actual expected `shouldSatisfy` all (< 1e-12)
    forM_ (take 4 actual) $ \p -> norm (p ^-^ V3 0.5 0.5 0) `shouldSatisfy` (< 1e-12)
    length (nub (map sampleMaterial (take 4 (surfaceSamples completed)))) `shouldBe` 4
    faceOrders (surfaceFrame completed) `shouldMatchList` [FaceOrder (FaceId i) (FaceId 0) Below | i <- [1 .. 4]]

  -- From the recipe's spec, on the paper the reopening starts from: the
  -- corner lies folded under the centre, upside down. Turned towards -z,
  -- away from the reader, it comes back out; towards +z it would swing up
  -- through the centre, which the library refuses, though its flat end is
  -- the same.
  it "turns the folded corner by where it goes, so behind reopens it and in front is refused" $ do
    start <- require "the reopening's start" (case drop 4 starts of s : _ -> Just s; [] -> Nothing)
    reopen <- right (prepareFlap (EdgeId 8) (FaceId 2) 180 start)
    wrong <- right (prepareFlap (EdgeId 8) (FaceId 2) (-180) start)
    prepareFlapToward [EdgeId 8] (FaceId 2) 180 TowardMinusZ start `shouldBe` Right reopen
    prepareFlapToward [EdgeId 8] (FaceId 2) 180 TowardPlusZ start `shouldBe` Right wrong
    case checkFlap defaultSweepSettings wrong of
      Left FlapEndpointOrder {} -> pure ()
      other -> expectationFailure (show other)

  -- From the recipe's spec: the page's states survive a trip through FOLD
  -- with their material coordinates and orders.
  it "round-trips the illustrated states with their material coordinates and orders" $ do
    let page = pageFile blintzGallery states
    eitherDecode (encode page) `shouldBe` Right page
    forM_ (zip (otherFrames page) states) $ \(fr, (_, original)) -> do
      reloaded <- right (surfaceFromFrame fr)
      map sampleMaterial (surfaceSamples reloaded) `shouldBe` map (Just . sampleMaterial) (surfaceSamples original)
      faceOrders (surfaceFrame reloaded) `shouldBe` faceOrders (surfaceFrame original)

  -- The page, drawn from the run's turns: the open square, each turn
  -- halfway, and each record's end. Byte for byte the golden the recipe's
  -- page was, and now the guard that the run still folds the blintz the way
  -- it was shown equal to the recipe.
  it "draws the eleven-figure page, checked-blintz.svg, byte for byte" $ do
    svg <- right (pageSvg blintzGallery (pageFile blintzGallery states))
    goldenText "test/golden/checked-blintz.svg" svg

  -- E10: after the four corners, carrying corner south-east on in front about
  -- c1's hinge would turn it up through the centre square. The library
  -- refuses it at its start, and the whole run is refused.
  describe "refuses carrying the first corner on through the centre" $ do
    it "as FlapEndpointOrder, naming step 5, with no part of the run" $
      case runOn (carriedOn id) of
        Left err -> do
          refusalKindOf err `shouldBe` Just (RefusalKind "FlapEndpointOrder")
          explain err `shouldSatisfy` T.isPrefixOf "step 5"
        Right run -> expectationFailure ("expected the run refused, and it made " <> show (length (runRecords run)) <> " records")

    -- Wrapped, the refusal is what the sequence says to expect: the run
    -- succeeds, the move leaves no record, and the run keeps the outcome.
    it "and runs to four records when the sequence expects that refusal" $ do
      run <- right (runOn (carriedOn (ExpectRefused (RefusalKind "FlapEndpointOrder"))))
      length (runRecords run) `shouldBe` 4
      runExpected run `shouldBe` [ExpectedRefusal 5 1 (RefusalKind "FlapEndpointOrder")]

    it "and refuses the run when it expects the refusal by another name" $
      case runOn (carriedOn (ExpectRefused (RefusalKind "FlapCovered"))) of
        Left (StepRefused 5 _ _ failure) -> failure `shouldBe` RefusedDifferently (RefusalKind "FlapCovered") (RefusalKind "FlapEndpointOrder")
        other -> expectationFailure ("expected the expectation refused, got " <> show (fmap (length . runRecords) other))

  it "refuses an expected refusal that does not come" $
    case runOn (oneMoreFold (ExpectRefused (RefusalKind "FlapEndpointOrder") (Fold MountainFold ToFlat (cornerOf SouthEast `onto` centre) FlapOfFirstArgument Nothing))) of
      Left (StepRefused 1 _ _ failure) -> failure `shouldBe` RefusalNotRaised (RefusalKind "FlapEndpointOrder")
      other -> expectationFailure ("expected the missing refusal refused, got " <> show (fmap (length . runRecords) other))

  it "refuses hinge of a step that made no turn" $
    case runOn hingeOfNothing of
      Left (ResolveRefused _ _ _ problem) -> problem `shouldBe` HingeOfNotOneMove (Name "c1") 0
      other -> expectationFailure ("expected hinge of refused, got " <> show (fmap (length . runRecords) other))
  where
    -- The blintz's four corners, then a fifth move made from the step c1.
    carriedOn wrap = sequenceOf (header "Blintz, then carry a corner on" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
      c1 <- step "c1" "Fold the south-east corner behind, to the centre." (fold mountain (cornerOf SouthEast `onto` centre))
      forM_ [NorthEast, NorthWest, SouthWest] $ \c -> step_ "Fold the next corner behind, to the centre." (fold mountain (cornerOf c `onto` centre))
      step_ "Carry the first corner on, in front." (move (wrap (Fold ValleyFold (Degrees 180) (hingeOf c1) FlapOfFirstArgument (Just (cornerOf SouthEast)))))
    oneMoreFold inner = sequenceOf (header "One fold" (sheetFile "examples/blintz-base.fold") (Just centre)) (step_ "Fold." (move inner))
    -- c1 is a step whose only move is turned back to where it already is: an
    -- unfold of a step never folded makes no record, so c1 has none.
    hingeOfNothing :: Sequence
    hingeOfNothing = sequenceOf (header "No hinge" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
      c0 <- step "c0" "Fold the corner." (fold mountain (cornerOf SouthEast `onto` centre))
      step_ "Open it." (unfold [c0])
      c1 <- step "c1" "Open it again, which does nothing." (unfold [c0])
      step_ "Fold about c1's hinge." (move (Fold ValleyFold ToFlat (hingeOf c1) FlapOfFirstArgument (Just (cornerOf SouthEast))))

-- | The fold a turn started from: the sheet's working pattern with the angles
-- and layer orders of the record's surface before the turn.
startOf :: Frame -> MoveRecord -> Either FoldingError Folded
startOf paper record = foldFrameWith paper {edgesFoldAngle = fst (recordAngles record), faceOrders = faceOrders (surfaceFrame (recordBefore record))}

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    pairs = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- pairs, Just p <- [lookup a points], Just q <- [lookup b points]]

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

require :: String -> Maybe a -> IO a
require label = maybe (fail ("missing " ++ label)) pure

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
