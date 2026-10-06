-- | The blintz, run as a sequence, against the study's hand-written recipe for
-- it: the first of the two migrations PRDs\/09 §9 plans, and the end of
-- #282. The recipe folds by hard-coded edge and face ids; the sequence names
-- its paper by compass words and resolves them. If the run's working pattern
-- differed from the recipe's in its face numbering, its rings or its layer
-- orders, the angles, the orders or the drawn page below would differ.
--
-- Both are built once, by 'runIO' at the top, as the recipe's own spec does.
module Senbazuru.Sequence.BlintzRunSpec (spec) where

import BlintzGallery (blintzSvg)
import BlintzSequence (BlintzMove (..), blintzFile, blintzStates, buildBlintzSequence)
import Control.Monad (forM_)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Sample (..), surfaceFrame, surfaceSamples)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (MoveFailure (..), ResolveProblem (..), SequenceError (..), refusalKindOf)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Syntax (Amount (..), Corner (..), Layers (..), Move (..), Name (..), RefusalKind (..), Sense (..), Sequence)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz)

spec :: Spec
spec = describe "the blintz, run as a sequence" $ do
  file <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  recipe <- runIO (right (buildBlintzSequence (keyFrame file)))
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" file) . elaborate
  records <- runIO (right (runRecords <$> runOn blintz))

  it "makes the recipe's five turns, one record each" $
    length records `shouldBe` length recipe

  it "ends every move with the recipe's crease angles, exactly" $
    map (snd . recordAngles) records `shouldBe` map (edgesFoldAngle . surfaceFrame . blintzEnd) recipe

  it "ends every move with the recipe's layer orders" $
    forM_ (zip records recipe) $ \(record, move') -> do
      let ours = faceOrders (surfaceFrame (recordAfter record))
          theirs = faceOrders (surfaceFrame (blintzEnd move'))
      length ours `shouldBe` length theirs
      ours `shouldMatchList` theirs

  it "keeps every point of paper where the recipe has it, within 1e-12" $
    forM_ (zip records recipe) $ \(record, move') -> do
      let ours = surfaceSamples (recordAfter record)
          theirs = surfaceSamples (blintzEnd move')
      map sampleMaterial ours `shouldBe` map sampleMaterial theirs
      maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) ours theirs) `shouldSatisfy` (<= 1e-12)

  -- The recipe's page, drawn through the recipe's own page function from the
  -- run's turns: each turn's start and halfway pose, and each record's end.
  -- Byte for byte the golden the recipe's spec keeps.
  it "draws the recipe's page, checked-blintz.svg, byte for byte" $ do
    turns <- mapM turnOf records
    states <- right (blintzStates [move' {blintzMotion = turn, blintzEnd = recordAfter record} | (move', record, turn) <- zip3 recipe records turns])
    svg <- right (blintzSvg (blintzFile states))
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
    turnOf record = case recordEvidence record of
      SweptHinge turn -> pure turn
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

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
