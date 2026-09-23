-- |
-- Tests for the pass that expands @let@ and @fold and unfold@.
--
-- __Examples__ pin the expansion and its provenance exactly: the quarter
-- fold, which has nothing to expand, as the design works through it; a
-- source with a @let@ and a @fold and unfold@, with the span each core move
-- remembers; and each place a @let@ can be used or hidden.
--
-- __Properties__ over the sequences "Test.CheckedSequenceGen" makes, which
-- use their @let@s in every position a point or a line can stand. They say
-- what must hold of any expansion: the steps are kept as written; no line is
-- left named, and the only point names left are marks'; and the origins,
-- read in order, give back every move the author wrote but the @let@s, with
-- a @fold and unfold@ as its two halves.
module Senbazuru.Sequence.ElaborateSpec (spec) where

import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Senbazuru.Sequence.Check
import Senbazuru.Sequence.Elaborate
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Syntax
import Test.CheckedSequenceGen (genChecked)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Property, checkCoverage, counterexample, cover, forAll, property, (===))
import Test.SequenceExamples (blintz)
import Test.SequenceHelpers (allMoves, sourceOf)

spec :: Spec
spec = do
  describe "a sequence with nothing to expand" $ do
    -- PRD 01 §5.1: the quarter fold's two folds are the whole of it.
    it "gives the quarter fold's two folds back, one core move each, remembering each" $ do
      text <- TIO.readFile "test/fixtures/quarter-fold.foldseq"
      let written = parseSequence "quarter.foldseq" text
      fmap (map (map coreMove . elaboratedMoves) . elaboratedSteps) (elaborated written)
        `shouldBe` Right
          [ [CoreFold MountainFold ToFlat (LineOnto (EdgeOf West) (EdgeOf East) Nothing) FlapOfFirstArgument Nothing],
            [CoreFold ValleyFold ToFlat (LineOnto (EdgeOf North) (EdgeOf South) Nothing) FlapOfFirstArgument Nothing]
          ]
      fmap (map (map coreOrigin . elaboratedMoves) . elaboratedSteps) (elaborated written)
        `shouldBe` fmap (map (map (\(Located sp m) -> Origin sp m WholeMove) . stepMoves . locValue) . seqSteps) written

    it "keeps the steps' names, captions and spans, and the header" $ do
      text <- TIO.readFile "test/fixtures/quarter-fold.foldseq"
      let written = parseSequence "quarter.foldseq" text
      fmap (map stepAsWritten . elaboratedSteps) (elaborated written)
        `shouldBe` fmap (map (\(Located sp s) -> (stepName s, stepCaption s, sp)) . seqSteps) written
      fmap elaboratedHeader (elaborated written) `shouldBe` fmap seqHeader written

    it "keeps a step's name in an unfold, and gives a built sequence's moves no span" $ do
      let moves = concatMap elaboratedMoves . elaboratedSteps . elaborate <$> checkSequence blintz
      fmap (map coreMove) moves
        `shouldBe` Right
          ( [CoreFold MountainFold ToFlat (Onto (CornerOf corner) Centre) FlapOfFirstArgument Nothing | corner <- [SouthEast, NorthEast, NorthWest, SouthWest]]
              <> [CoreUnfold ["c1"]]
          )
      fmap (all ((== NoSpan) . originSpan . coreOrigin)) moves `shouldBe` Right True

  describe "every field of a move" $
    -- Every field here is something other than its default, so a field the
    -- expansion dropped or replaced would show. The properties below look
    -- only at names and origins.
    it "comes through unchanged where there is nothing to expand" $
      fmap
        (map (map coreMove . elaboratedMoves) . elaboratedSteps)
        ( elaborated
            ( parseSequence
                "t"
                ( sourceOf
                    [ "step a { fold mountain 45° edge west top 2 layers moving centre }",
                      "step m { rabbit-ear at centre until 120° sample 30° 60° }",
                      "step { fold and unfold valley edge north all layers flap containing corner north-east; rotate 3/8 turn anticlockwise; turn over top-bottom; continue m until 150°; unfold a m; not modelled \"swivel fold\" }"
                    ]
                )
            )
        )
        `shouldBe` Right
          [ [CoreFold MountainFold (Degrees 45) (EdgeOf West) (TopLayers 2) (Just Centre)],
            [CoreMacro (RabbitEar Centre 120) [30, 60]],
            [ CoreFold ValleyFold ToFlat (EdgeOf North) AllLayers (Just (CornerOf NorthEast)),
              CoreUnfoldPrevious,
              CoreRotate 3 Anticlockwise,
              CoreTurnOver TopBottom,
              CoreContinue "m" 150,
              CoreUnfold ["a", "m"],
              CoreNotModelled "swivel fold"
            ]
          ]

  describe "a let and a fold and unfold" $ do
    let source =
          sourceOf
            [ "step half \"Crease the middle.\" {",
              "  let mid = edge west to edge east",
              "  fold and unfold valley mid",
              "}",
              "step {",
              "  let p = corner south-west",
              "  mark m = centre",
              "  fold valley p to centre",
              "  fold valley m to mid moving p",
              "}"
            ]
        middle = LineOnto (EdgeOf West) (EdgeOf East) Nothing
        steps = map elaboratedMoves . elaboratedSteps <$> elaborated (parseSequence "t" source)

    it "become the moves they stand for" $
      fmap (map (map coreMove)) steps
        `shouldBe` Right
          [ [CoreFold ValleyFold ToFlat middle FlapOfFirstArgument Nothing, CoreUnfoldPrevious],
            [ CoreMark "m" Centre Nothing,
              CoreFold ValleyFold ToFlat (Onto (CornerOf SouthWest) Centre) FlapOfFirstArgument Nothing,
              CoreFold ValleyFold ToFlat (PointToLine (PointNamed "m") middle) FlapOfFirstArgument (Just (CornerOf SouthWest))
            ]
          ]

    -- Both halves are the one line the author wrote, line 5, and a refusal of
    -- either quotes it and points there. The let left no move behind.
    it "remember the author's line, both halves of the fold and unfold the same one" $
      fmap (map coreOrigin . concat . take 1) steps
        `shouldBe` Right
          [ Origin (Span "t" 5 3 5 29) (FoldAndUnfold ValleyFold (LineNamed "mid") FlapOfFirstArgument Nothing) FoldHalf,
            Origin (Span "t" 5 3 5 29) (FoldAndUnfold ValleyFold (LineNamed "mid") FlapOfFirstArgument Nothing) UnfoldHalf
          ]

    it "remember the move as written, let names and all, where a let was used" $
      fmap (map (originWritten . coreOrigin) . concat . drop 1) steps
        `shouldBe` Right
          [ Mark "m" Centre Nothing,
            Fold ValleyFold ToFlat (Onto (PointNamed "p") Centre) FlapOfFirstArgument Nothing,
            Fold ValleyFold ToFlat (PointToLine (PointNamed "m") (LineNamed "mid")) FlapOfFirstArgument (Just (PointNamed "p"))
          ]

  describe "a let" $ do
    it "of another let ends as the construction underneath" $
      oneStepCores "step { let a = centre; let b = midpoint of [a, corner north-east]; anchor b }"
        `shouldBe` Right [CoreAnchor (MidpointOf Centre (CornerOf NorthEast))]

    it "inside a together is in scope for the rest of the block and after it" $ do
      let crease = LineOnto (EdgeOf North) (EdgeOf South) Nothing
      fmap (map (coreMove . withoutOrigin)) (oneStep "step { together { let d = edge north to edge south; fold valley d moving centre }; fold valley d moving corner south-west }")
        `shouldBe` Right
          [ CoreTogether [bare (CoreFold ValleyFold ToFlat crease FlapOfFirstArgument (Just Centre))],
            CoreFold ValleyFold ToFlat crease FlapOfFirstArgument (Just (CornerOf SouthWest))
          ]

    it "is expanded in a mirror or a turn, a layer order, a macro-move and a pose" $
      fmap
        (map (map coreMove . elaboratedMoves) . elaboratedSteps)
        ( elaborated
            ( parseSequence
                "t"
                ( sourceOf
                    [ "step a { let o = centre; let q = corner north-east; fold valley q to o }",
                      "step { repeat a turned 1/4 about o; checkpoint \"x.fold\" { layers q above o }; collapse at o keeping [q, o] flat until 90°; pose { crease [o, q] at -90° } }"
                    ]
                )
            )
        )
        `shouldBe` Right
          [ [CoreFold ValleyFold ToFlat (Onto (CornerOf NorthEast) Centre) FlapOfFirstArgument Nothing],
            [ CoreRepeat "a" Nothing (Just (TurnedQuarters 1 Centre)),
              CoreCheckpoint "x.fold" (Relations [LayerAbove (CornerOf NorthEast) Centre]),
              CoreMacro (Collapse Centre (Just (CornerOf NorthEast, Centre)) 90) [],
              CorePose [(Centre, CornerOf NorthEast, -90)]
            ]
          ]

    it "is expanded inside an expectation, and a let there is expected to be refused in vain" $ do
      fmap (map (coreMove . withoutOrigin)) (oneStep "step { let l = edge north; expect refused FlapCovered { fold valley l moving centre }; turn over left-right }")
        `shouldBe` Right
          [ CoreExpectRefused (RefusalKind "FlapCovered") [bare (CoreFold ValleyFold ToFlat (EdgeOf North) FlapOfFirstArgument (Just Centre))],
            CoreTurnOver LeftRight
          ]
      -- A let can never be refused, so expecting one expects nothing.
      oneStepCores "step { expect refused FlapCovered { let l = edge north }; turn over left-right }"
        `shouldBe` Right [CoreExpectRefused (RefusalKind "FlapCovered") [], CoreTurnOver LeftRight]

    -- The checker forgets the let, so the name may be given again. Were the
    -- expansion to remember it, the mark's name would be read as the let's
    -- point.
    it "inside an expectation is forgotten, so a mark given its name after is the mark" $
      oneStepCores "step { expect refused FlapCovered { let x = centre }; mark x = corner north-east; anchor x }"
        `shouldBe` Right [CoreExpectRefused (RefusalKind "FlapCovered") [], CoreMark "x" (CornerOf NorthEast) Nothing, CoreAnchor (PointNamed "x")]

  describe "a move inside an expectation" $ do
    -- It has no span of its own, so it takes the expectation's.
    it "is remembered as written, at the expectation's span" $ do
      let moves = oneStep "step { expect refused FlapCovered { fold valley edge west moving centre } }"
          atTheExpectation m = [(originSpan (coreOrigin m), Fold ValleyFold ToFlat (EdgeOf West) FlapOfFirstArgument (Just Centre), WholeMove)]
      fmap length moves `shouldBe` Right 1
      fmap (map insideOrigins) moves `shouldBe` fmap (map atTheExpectation) moves

    it "is both halves of a fold and unfold, either of which may be the one refused" $
      fmap (map insideParts) (oneStep "step { expect refused ExistingHingeFlat { fold and unfold valley edge west moving centre } }")
        `shouldBe` Right [[(CoreFold ValleyFold ToFlat (EdgeOf West) FlapOfFirstArgument (Just Centre), FoldHalf), (CoreUnfoldPrevious, UnfoldHalf)]]

  describe "any sequence that means something" $ do
    prop "keeps its steps as written, and its header" $
      forAll genChecked $ \s -> withChecked s $ \checked ->
        let e = elaborate checked
         in (elaboratedHeader e, map stepAsWritten (elaboratedSteps e))
              === (seqHeader s, map (\(Located sp x) -> (stepName x, stepCaption x, sp)) (seqSteps s))

    prop "leaves no line named, and names no point but a mark" $
      checkCoverage . forAll genChecked $ \s ->
        cover 30 (any isLet (allMoves s)) "had a let to expand" $
          withChecked s $ \checked ->
            let cores = concatMap elaboratedMoves (elaboratedSteps (elaborate checked))
                marks = Set.fromList [name | Mark (Name name) _ _ <- allMoves s]
             in counterexample (show (map coreMove cores)) $
                  (namesAfter "LineNamed" cores, filter (`Set.notMember` marks) (namesAfter "PointNamed" cores)) === ([], [])

    prop "remembers every move the author wrote, in order, a fold and unfold as its two halves" $
      checkCoverage . forAll genChecked $ \s ->
        cover 15 (any isFoldAndUnfold (allMoves s)) "had a fold and unfold" $
          withChecked s $ \checked ->
            let written = map (map locValue . stepMoves . locValue) (seqSteps (checkedSequence checked))
                cores = map elaboratedMoves (elaboratedSteps (elaborate checked))
             in property (length written == length cores && and (zipWith originsFollow written cores))

elaborated :: Either SequenceError Sequence -> Either SequenceError Elaborated
elaborated parsed = elaborate <$> (parsed >>= checkSequence)

-- | The core moves of a source of one step, written on line 3.
oneStep :: Text -> Either SequenceError [CoreMove]
oneStep step = concatMap elaboratedMoves . elaboratedSteps <$> elaborated (parseSequence "t" (sourceOf [step]))

oneStepCores :: Text -> Either SequenceError [Core]
oneStepCores = fmap (map coreMove) . oneStep

stepAsWritten :: ElaboratedStep -> (Maybe Name, Maybe Text, Span)
stepAsWritten s = (elaboratedName s, elaboratedCaption s, elaboratedSpan s)

withChecked :: Sequence -> (Checked -> Property) -> Property
withChecked s k = case checkSequence s of
  Right checked -> k checked
  Left err -> counterexample ("the generator made a sequence the checker refuses: " <> show err) False

-- | For an expectation, what its origin says of each move inside it.
insideOrigins :: CoreMove -> [(Span, Move, Part)]
insideOrigins m = case coreMove m of
  CoreExpectRefused _ inside -> [(originSpan o, originWritten o, originPart o) | o <- map coreOrigin inside]
  _ -> []

insideParts :: CoreMove -> [(Core, Part)]
insideParts m = case coreMove m of
  CoreExpectRefused _ inside -> [(coreMove c, originPart (coreOrigin c)) | c <- inside]
  _ -> []

-- | Whether the core moves' origins give back these written moves in order:
-- a @let@ gives none, a @fold and unfold@ its two halves, anything else one,
-- and the moves inside a block give back the block's.
originsFollow :: [Move] -> [CoreMove] -> Bool
originsFollow written cores = case written of
  [] -> null cores
  Let {} : rest -> originsFollow rest cores
  m@FoldAndUnfold {} : rest -> case cores of
    first : second : more ->
      origin first == (m, FoldHalf) && origin second == (m, UnfoldHalf) && originsFollow rest more
    _ -> False
  m : rest -> case cores of
    c : more -> origin c == (m, WholeMove) && inside m (coreMove c) && originsFollow rest more
    [] -> False
  where
    origin c = (originWritten (coreOrigin c), originPart (coreOrigin c))
    inside m c = case (m, c) of
      (Together members, CoreTogether cores') -> originsFollow (map locValue members) cores'
      (ExpectRefused _ inner, CoreExpectRefused _ cores') -> originsFollow [inner] cores'
      (Together _, _) -> False
      (ExpectRefused {}, _) -> False
      _ -> True

-- | The names after a constructor in the core moves' 'show', origins left out:
-- @PointNamed (Name "m")@ gives @m@. The generator's names hold no quote.
namesAfter :: Text -> [CoreMove] -> [Text]
namesAfter constructor cores =
  [T.takeWhile (/= '"') (T.drop (T.length marker) rest) | (_, rest) <- T.breakOnAll marker (T.pack (show (map withoutOrigin cores)))]
  where
    marker = constructor <> " (Name \""

-- | A core move with its origin, and those of the moves inside it, blanked,
-- so that its 'show' holds only what the run is given.
withoutOrigin :: CoreMove -> CoreMove
withoutOrigin (CoreMove _ core) = bare $ case core of
  CoreTogether members -> CoreTogether (map withoutOrigin members)
  CoreExpectRefused kind inside -> CoreExpectRefused kind (map withoutOrigin inside)
  other -> other

-- | A core move with a blank origin.
bare :: Core -> CoreMove
bare = CoreMove (Origin NoSpan (TurnOver LeftRight) WholeMove)

isLet :: Move -> Bool
isLet = \case
  Let {} -> True
  _ -> False

isFoldAndUnfold :: Move -> Bool
isFoldAndUnfold = \case
  FoldAndUnfold {} -> True
  _ -> False
