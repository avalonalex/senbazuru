-- |
-- Tests for the static checker: what it refuses, where it says the problem
-- is, and the one thing it changes in a sequence it accepts.
--
-- __One example for every refusal.__ Most are written as text, parsed and then
-- checked, because a few words of source say what is wrong more plainly than
-- the tree does, and because it shows that parsed input is refused like built
-- input. Each asserts the /problem/ and the /place/, never the wording. The
-- wording has its own spec.
--
-- __The values only Haskell can make__ are built, since no text spells them.
-- They are the reason a checked sequence can always be printed and read back,
-- so each has an example here, and a property over random trees holds the
-- whole promise in the parser's spec.
--
-- __Where a refusal says it is.__ A built sequence has no positions, so the
-- message has to open with the step, and there is nothing to point a caret
-- at. The same mistake in text gets the same message and a location as well.
--
-- __What checking changes.__ The parser reads a bare name beside @to@ as a
-- point, whatever it names. The checker knows what it names, and the tests
-- here pin each of the four shapes it rewrites, and that nothing else moves.
module Senbazuru.Sequence.CheckSpec (spec) where

import Control.Monad (void)
import Data.Foldable (for_)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Senbazuru.Explain (explain)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Syntax
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = do
  describe "a sequence that means something" $ do
    it "accepts the blintz and the quarter fold, and hands them back unchanged" $
      for_ [blintz, quarterFold] $ \s ->
        fmap checkedSequence (checkSequence s) `shouldBe` Right s

    it "accepts the blintz as an author typed it" $ do
      text <- TIO.readFile "blintz.foldseq"
      outcome text `shouldBe` Accepted

    -- A step's name is usable as soon as the step has closed.
    it "lets a step be named by the one after it" $
      outcomeOf ["step a { " <> aFold <> " }", "step { unfold a; fold valley hinge of a moving centre }"] `shouldBe` Accepted

  describe "a bare name beside to" $ do
    -- The design's own example: the parser reads both names as points.
    it "is given its kind: a point laid onto a line's name" $
      lastLineOf ["step { let a = corner south-west; let b = edge north; fold valley a to b }"]
        `shouldBe` Right (PointToLine (PointNamed "a") (LineNamed "b"))

    it "is given its kind: one line's name laid onto another's" $
      lastLineOf ["step { let a = edge south; let b = edge north; fold valley a to b }"]
        `shouldBe` Right (LineOnto (LineNamed "a") (LineNamed "b") Nothing)

    it "is given its kind: a line's name laid onto a line written out" $
      lastLineOf ["step { let a = edge south; fold valley a to edge north }"]
        `shouldBe` Right (LineOnto (LineNamed "a") (EdgeOf North) Nothing)

    it "is left alone when both names are points" $
      lastLineOf ["step { let a = corner south-west; mark b = centre; fold valley a to b }"]
        `shouldBe` Right (Onto (PointNamed "a") (PointNamed "b"))

    -- @let n = b@ was read as a point too. Once it is known to be a line, so
    -- is @n@, which the fold after it depends on: a bare name standing alone
    -- as a fold line has to be a line's.
    it "is given its kind in a let, and the new name takes that kind" $
      fmap movesOf (checkText ["step { let b = edge north; let n = b; fold valley n moving centre }"])
        `shouldBe` Right
          [ Let "b" (BindLine (EdgeOf North)),
            Let "n" (BindLine (LineNamed "b")),
            Fold ValleyFold ToFlat (LineNamed "n") FlapOfFirstArgument (Just Centre)
          ]

    -- Nothing but those names may change, and 'canonical' is what undoes the
    -- change. So the two canonical forms are equal.
    it "changes nothing else" $
      for_ kindSources $ \steps -> do
        let parsed = parseSequence "t" (sourceOf steps)
        fmap (canonical . checkedSequence) (parsed >>= checkSequence) `shouldBe` fmap canonical parsed

    it "refuses a line laid onto a point, blaming the name that is wrong" $ do
      outcomeOf ["step { let l = edge north; mark p = centre; fold valley l to p }"]
        `shouldBe` Refused (InStep 1 Nothing) (WrongKind "p" LineName PointName)
      outcomeOf ["step { let l = edge north; fold valley l to centre }"]
        `shouldBe` Refused (InStep 1 Nothing) (WrongKind "l" PointName LineName)

  describe "every refusal, by its problem and its place" $
    for_ refusals $ \(label, steps, place, problem) ->
      it label $ outcomeOf steps `shouldBe` Refused place problem

  describe "what is allowed, next to what is not" $ do
    it "lets a step of nothing but expect refused stand, since it is not empty" $
      outcomeOf ["step { expect refused FlapCovered { " <> aFold <> " } }"] `shouldBe` Accepted

    it "lets a plain repeat carry a model line, which only a mirror or a turn cannot" $
      outcomeOf ["step m { fold valley model [(0, 0), (1, 1)] moving centre }", "step { repeat m }"] `shouldBe` Accepted

    it "takes a let of an exact point as exact, and a mark as not" $ do
      outcomeOf ["step a { let o = centre; " <> aFold <> " }", "step { repeat a turned 1/4 about o }"] `shouldBe` Accepted
      outcomeOf ["step a { mark o = centre; " <> aFold <> " }", "step { repeat a turned 1/4 about o }"]
        `shouldBe` Refused (InStep 2 Nothing) (RepeatUnmappable "a" IsometryByConstruction)

    it "lets hinge of name a step that marks a point and turns paper once" $
      outcomeOf ["step one { mark p = centre; " <> aFold <> " }", "step { fold valley hinge of one moving centre }"] `shouldBe` Accepted

    it "lets a range name one step twice" $
      outcomeOf ["step a { " <> aFold <> " }", "step { repeat a..a }"] `shouldBe` Accepted

  describe "a value only Haskell can make" $
    for_ builtRefusals $ \(label, built', place, problem) ->
      it label $ builtOutcome built' `shouldBe` Refused place problem

  describe "where a refusal says it is" $ do
    it "opens every message with the step or the header, since a built sequence has nothing else" $ do
      for_ refusals $ \(label, steps, place, _) ->
        (label, startsWithPlace place (parseSequence "t" (sourceOf steps) >>= checkSequence)) `shouldBe` (label, True)
      for_ builtRefusals $ \(label, built', place, _) ->
        (label, startsWithPlace place (checkSequence built')) `shouldBe` (label, True)

    -- The design's example: the step is counted from 1 and named.
    it "names step 2 (c1) for a name given twice, with no location, in a built sequence" $ do
      let twice = sequenceOf (header "T" sheetSquare Nothing) $ do
            _ <- step "c1" "Fold." (fold valley (cornerOf SouthEast `onto` centre))
            _ <- step "c1" "Fold again." (fold valley (cornerOf NorthEast `onto` centre))
            pure ()
      case checkSequence twice of
        Left err -> do
          explain err `shouldSatisfy` T.isPrefixOf "step 2 (c1): "
          sourceLocation err `shouldBe` Nothing
          excerpt "" err `shouldBe` Nothing
        Right _ -> expectationFailure "a name given twice was accepted"

    it "gives the same refusal of parsed text a location, at the move" $ do
      let text = sourceOf ["step a { " <> aFold <> " }", "step {", "  turn over left-right", "  unfold c9   # no such step", "}"]
      case parseSequence "crane.foldseq" text >>= checkSequence of
        Left err -> do
          err `shouldBe` StaticRefused (InStep 2 Nothing) (Span "crane.foldseq" 6 3 6 12) (UnknownName "c9")
          sourceLocation err `shouldBe` Just "crane.foldseq:6:3"
          excerpt text err `shouldBe` Just "  |\n6 |   unfold c9   # no such step\n  |   ^^^^^^^^^"
        Right _ -> expectationFailure "an unknown name was accepted"

    it "points at the header's own line for a problem there, and at a together's own member" $ do
      fmap errorSpan (leftOf (parseSequence "t" "foldseq 1\nsheet square\nanchor a\nstep { turn over left-right }\n" >>= checkSequence))
        `shouldBe` Just (Span "t" 3 1 3 9)
      fmap errorSpan (leftOf (checkText ["step {", "  together {", "    turn over left-right", "    rotate 9/8 turn clockwise", "  }", "}"]))
        `shouldBe` Just (Span "t" 6 5 6 30)

-- | What a test sees of a check.
data Outcome = Accepted | Refused Place StaticProblem | DidNotParse Text
  deriving stock (Eq, Show)

-- | A fold that is fine anywhere, for the steps that need one.
aFold :: Text
aFold = "fold valley corner south-east to centre"

-- | A source with a plain square sheet and these lines after its header. The
-- steps start on line 3.
sourceOf :: [Text] -> Text
sourceOf steps = T.unlines ("foldseq 1" : "sheet square" : steps)

checkText :: [Text] -> Either SequenceError Checked
checkText steps = parseSequence "t" (sourceOf steps) >>= checkSequence

outcome :: Text -> Outcome
outcome text = case parseSequence "t" text of
  Left err -> DidNotParse (explain err)
  Right parsed -> builtOutcome parsed

outcomeOf :: [Text] -> Outcome
outcomeOf = outcome . sourceOf

builtOutcome :: Sequence -> Outcome
builtOutcome s = case checkSequence s of
  Right _ -> Accepted
  Left (StaticRefused place _ problem) -> Refused place problem
  Left err@(ParseFailed _) -> DidNotParse (explain err)

movesOf :: Checked -> [Move]
movesOf = concatMap (map locValue . stepMoves . locValue) . seqSteps . stripSpans . checkedSequence

-- | The line of the last fold in a checked source.
lastLineOf :: [Text] -> Either SequenceError Line
lastLineOf steps = do
  checked <- checkText steps
  case [line | Fold _ _ line _ _ <- movesOf checked] of
    [] -> Left (StaticRefused InHeader NoSpan EmptyStep)
    lines' -> Right (last lines')

leftOf :: Either a b -> Maybe a
leftOf = either Just (const Nothing)

startsWithPlace :: Place -> Either SequenceError a -> Bool
startsWithPlace place = \case
  Left err -> T.isPrefixOf (opening <> ": ") (explain err)
  Right _ -> False
  where
    opening = case place of
      InHeader -> "header"
      InStep n Nothing -> "step " <> T.pack (show n)
      InStep n (Just (Name name)) -> "step " <> T.pack (show n) <> " (" <> name <> ")"

-- | The sources whose bare names the checker gives a kind to.
kindSources :: [[Text]]
kindSources =
  [ ["step { let a = corner south-west; let b = edge north; fold valley a to b }"],
    ["step { let a = edge south; let b = edge north; fold valley a to b }"],
    ["step { let a = edge south; fold valley a to edge north }"],
    ["step { let b = edge north; let n = b; fold valley n moving centre }"],
    ["step { let a = corner south-west; mark b = centre; fold valley a to b }"]
  ]

-- | Every refusal text can reach: a label, the steps of a source, and the
-- place and problem it must be refused with.
refusals :: [(String, [Text], Place, StaticProblem)]
refusals =
  [ ("a name nothing defines", ["step { unfold c9 }"], InStep 1 Nothing, UnknownName "c9"),
    ("a name used before the step that gives it", ["step { unfold later }", "step later { turn over left-right }"], InStep 1 Nothing, UnknownName "later"),
    ("a name in the header, where none is defined yet", ["anchor a", "step { turn over left-right }"], InHeader, UnknownName "a"),
    ("a step's own name used inside it: not usable until the step closes", ["step a { " <> aFold <> "; unfold a }"], InStep 1 (Just "a"), UnknownName "a"),
    ("a mark of itself", ["step { mark a = a }"], InStep 1 Nothing, UnknownName "a"),
    ("a step's own name given again inside it: taken as soon as the step opens", ["step a { mark a = centre }"], InStep 1 (Just "a"), DuplicateName "a"),
    ("one name for a mark and a let", ["step s { mark p = centre; let p = centre }"], InStep 1 (Just "s"), DuplicateName "p"),
    ("one name for two steps", ["step s { " <> aFold <> " }", "step s { " <> aFold <> " }"], InStep 2 (Just "s"), DuplicateName "s"),
    ("a point's name standing alone as a fold line", ["step { mark p = centre; fold valley p moving centre }"], InStep 1 Nothing, WrongKind "p" LineName PointName),
    ("a step's name where a point belongs", ["step s { " <> aFold <> " }", "step { anchor s }"], InStep 2 Nothing, WrongKind "s" PointName StepName),
    ("a step's name beside to", ["step s { " <> aFold <> " }", "step { fold valley s to centre }"], InStep 2 Nothing, WrongKind "s" PointName StepName),
    ("a point's name where a step belongs", ["step { mark p = centre; unfold p }"], InStep 1 Nothing, WrongKind "p" StepName PointName),
    ("a line's name where only a point can stand", ["step { let l = edge north; anchor l }"], InStep 1 Nothing, WrongKind "l" PointName LineName),
    ("a name given only inside expect refused, which never happens", ["step { expect refused FlapCovered { mark m = centre }; anchor m }"], InStep 1 Nothing, UnknownName "m"),
    ("a step with no move", ["step { }"], InStep 1 Nothing, EmptyStep),
    ("a step with nothing but lets", ["step only { let a = centre; let b = edge north }"], InStep 1 (Just "only"), EmptyStep),
    ("unfolding a step that draws nothing", ["step e { expect refused FlapCovered { " <> aFold <> " } }", "step { unfold e }"], InStep 2 Nothing, NotAFigure "e"),
    ("repeating a step that draws nothing", ["step e { expect refused FlapCovered { " <> aFold <> " } }", "step { repeat e }"], InStep 2 Nothing, NotAFigure "e"),
    ("no eighths", ["step { rotate 0/8 turn clockwise }"], InStep 1 Nothing, NotEighths 0),
    ("a whole turn of eighths", ["step { rotate 8/8 turn clockwise }"], InStep 1 Nothing, NotEighths 8),
    ("a whole turn of quarters", ["step a { " <> aFold <> " }", "step { repeat a turned 4/4 about centre }"], InStep 2 Nothing, NotQuarters 4),
    ("a fraction beyond the far end", ["step { anchor fraction 3/2 along [corner south-west, corner north-east] }"], InStep 1 Nothing, RatioOutOfRange (3 / 2)),
    ("a macro-move taken past flat", ["step { collapse at centre until 200° }"], InStep 1 Nothing, ParameterOutOfRange 200 (Exclusive 0) (Inclusive 180)),
    ("a macro-move taken nowhere", ["step { petal top flap until 0° }"], InStep 1 Nothing, ParameterOutOfRange 0 (Exclusive 0) (Inclusive 180)),
    ("an in-between pose that is the end pose", ["step { rabbit-ear at centre until 90° sample 45° 90° }"], InStep 1 Nothing, ParameterOutOfRange 90 (Exclusive 0) (Exclusive 90)),
    ("a continue taken past flat", ["step m { collapse at centre until 90° }", "step { continue m until 181° }"], InStep 2 Nothing, ParameterOutOfRange 181 (Exclusive 0) (Inclusive 180)),
    ("a kind of refusal there is none of", ["step { expect refused FlapCoverd { " <> aFold <> " } }"], InStep 1 Nothing, UnknownRefusalKind (RefusalKind "FlapCoverd")),
    ("continuing a step that is a plain fold", ["step f { " <> aFold <> " }", "step { continue f until 90° }"], InStep 2 Nothing, NotASingleMacro "f"),
    ("continuing a step of two macro-moves", ["step two { together { collapse at centre until 90°; petal top flap until 90° } }", "step { continue two until 120° }"], InStep 2 Nothing, NotASingleMacro "two"),
    ("the hinge of a step that turned paper twice", ["step two { " <> aFold <> "; fold valley corner north-east to centre }", "step { fold valley hinge of two moving centre }"], InStep 2 Nothing, HingeOfSeveralMoves "two"),
    ("a turned repeat of a model line", ["step m { fold valley model [(0, 0), (1, 1)] moving centre }", "step { repeat m turned 1/4 about centre }"], InStep 2 Nothing, RepeatUnmappable "m" UsesModelCoordinates),
    ("a turned repeat of a model line behind a let", ["step m { let d = model [(0, 0), (1, 1)]; fold valley d moving centre }", "step { repeat m turned 1/4 about centre }"], InStep 2 Nothing, RepeatUnmappable "m" UsesModelCoordinates),
    ("a mirrored repeat of a count of layers", ["step c { fold valley edge west to edge east top 2 layers }", "step { repeat c mirrored across [corner south-west, corner north-east] }"], InStep 2 Nothing, RepeatUnmappable "c" CountsLayers),
    ("a repeat mirrored across a construction", ["step a { " <> aFold <> " }", "step { repeat a mirrored across [centre, meet edge north edge east] }"], InStep 2 Nothing, RepeatUnmappable "a" IsometryByConstruction),
    ("a turned range with a model line in the middle, named by the step that has it", ["step a { " <> aFold <> " }", "step b { fold valley model [(0, 0), (1, 1)] moving centre }", "step c { " <> aFold <> " }", "step { repeat a..c turned 2/4 about centre }"], InStep 4 Nothing, RepeatUnmappable "b" UsesModelCoordinates),
    ("a range that runs backwards", ["step a { " <> aFold <> " }", "step b { " <> aFold <> " }", "step { repeat b..a }"], InStep 3 Nothing, RangeRunsBackwards "b" "a")
  ]

-- | The values no text can spell, each in a sequence of one step.
builtRefusals :: [(String, Sequence, Place, StaticProblem)]
builtRefusals =
  [ ("a name of two words", named "two words", InStep 1 (Just "two words"), NotANameToken "two words"),
    ("a name of no letters at all", named "", InStep 1 (Just ""), NotANameToken ""),
    ("a name that starts with a digit", named "1st", InStep 1 (Just "1st"), NotANameToken "1st"),
    ("a reserved word as a step's name", named "north-west", InStep 1 (Just "north-west"), ReservedWordAsName "north-west"),
    ("a reserved word in capitals", named "North-West", InStep 1 (Just "North-West"), ReservedWordAsName "North-West"),
    ("a reserved word as a mark's name", oneStep (Mark "centre" Centre Nothing), InStep 1 Nothing, ReservedWordAsName "centre"),
    ("a reserved word as a let's name", oneStep (Let "edge" (BindPoint Centre)), InStep 1 Nothing, ReservedWordAsName "edge"),
    ("a count of no layers", oneStep (Fold ValleyFold ToFlat (EdgeOf West) (TopLayers 0) (Just Centre)), InStep 1 Nothing, LayerCountNotPositive 0),
    ("a count of no layers, folded and unfolded", oneStep (FoldAndUnfold ValleyFold (EdgeOf West) (TopLayers (-2)) (Just Centre)), InStep 1 Nothing, LayerCountNotPositive (-2)),
    ("a fold's angle with a sign", oneStep (Fold ValleyFold (Degrees (-90)) (EdgeOf West) FlapOfFirstArgument (Just Centre)), InStep 1 Nothing, SignNotAllowed (-90)),
    ("a macro-move taken backwards", oneStep (Macro (Collapse Centre Nothing (-5)) []), InStep 1 Nothing, ParameterOutOfRange (-5) (Exclusive 0) (Inclusive 180)),
    ("an in-between pose with a sign", oneStep (Macro (Petal TopFlapTip 90) [-30]), InStep 1 Nothing, ParameterOutOfRange (-30) (Exclusive 0) (Exclusive 90)),
    ("a fraction with a sign", oneStep (Anchor (FractionAlong (-(1 / 2)) Centre (CornerOf NorthEast))), InStep 1 Nothing, RatioOutOfRange (-(1 / 2))),
    ("eighths with a sign", oneStep (Rotate (-1) Clockwise), InStep 1 Nothing, NotEighths (-1)),
    ("an unfold of no steps", oneStep (Unfold []), InStep 1 Nothing, UnfoldNamesNothing)
  ]
  where
    named name = sequenceOf (header "T" sheetSquare Nothing) (void (stepUncaptioned name (turnOver LeftRight)))
    oneStep bad = sequenceOf (header "T" sheetSquare Nothing) (stepUncaptioned_ (move bad))
