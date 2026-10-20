-- |
-- Tests for the sequence language's error type, and for how an error reaches a
-- person.
--
-- Nothing here produces an error: each test builds one by hand and looks at
-- what comes out. Whether the parser raises the right one in the right place
-- is the parser's spec's to say. This one pins the three things every
-- producer of an error leans on.
--
-- __The shape of a message.__ A message is one line that can follow a colon:
-- no capital to open, no full stop to close, no path, and no word that only
-- makes sense at a command line. Nothing in the types says so, and a new
-- constructor is exactly where the rule gets broken, so every constructor of
-- 'StaticProblem' and 'Hint' is sampled. 'sampledStatic' and 'sampledHint'
-- match on every constructor with no catch-all, so a constructor added later
-- makes them incomplete, and the compiler says so. That is a reminder and not
-- a guarantee: the warning goes away when the new arm is added, whether or
-- not a sample was added beside it. The sample is the part that matters.
--
-- __The excerpt__, which is fiddly in ways that only show on a real line: the
-- caret must sit under the right character when the line holds a tab, must not
-- run past the end of the line, and must still appear for a span with no
-- width. The three examples the language's design prints are reproduced
-- character for character, location included.
--
-- __The list of refusal kinds__ is hand-written text that has to agree with
-- constructors elsewhere in the library. Some of its names exist as
-- constructors today, and a test reads each one's spelling off a real value.
-- And every kind the runner gives a refusal must be on it, or @expect
-- refused@ could never name it (#580). 'everyRefusal' holds one refusal of
-- each constructor 'refusalKindOf' looks at, and each must have its own
-- constructor's name as its kind, or none where the design lets no author
-- expect it (owner decisions 49 and 50). 'refusalKindOf' matches each of
-- those types with no catch-all, so a constructor added later warns there;
-- its sample goes here, which is again a reminder and not a guarantee.
module Senbazuru.Sequence.ErrorSpec (spec) where

import Data.Char (isAlphaNum, isUpper)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Query (CreaseEnd (..), FoldError (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Flap (FlapError (..))
import Senbazuru.Origami.Folding (FoldingError (..))
import Senbazuru.Origami.HingeSweep (SweepError (..))
import Senbazuru.Origami.Surface (SurfaceError (..))
import Senbazuru.Origami.ThroughLayers (ThroughError (..))
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), RefusalKind (..), Span (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "a message" $ do
    it "says something, for every static problem and every hint" $
      [who | (who, msg) <- everyMessage, T.null msg] `shouldBe` []

    it "does not open with a capital, so it can follow a colon" $
      [who | (who, msg) <- everyMessage, maybe False (isUpper . fst) (T.uncons msg)] `shouldBe` []

    it "ends without a full stop and stays on one line" $
      [who | (who, msg) <- everyMessage, "." `T.isSuffixOf` msg || T.any (== '\n') msg] `shouldBe` []

    -- A message is also read at a GHCi prompt and by the material study, where
    -- a command's name or a flag would mean nothing.
    it "names no command and no flag" $
      [who | (who, msg) <- everyMessage, any (`T.isInfixOf` msg) ["senbazuru", "--", " run "]] `shouldBe` []

  describe "a static refusal" $ do
    it "opens with its step and the step's name, the only place a Haskell author can look" $
      explain (StaticRefused (InStep 2 (Just "c1")) NoSpan (DuplicateName "c1"))
        `shouldBe` "step 2 (c1): \"c1\" is already defined, and a name can be given only once"

    it "opens with the step alone when it has no name, and with the header for a header line" $
      map (T.takeWhile (/= ':') . explain) [StaticRefused (InStep 3 Nothing) NoSpan EmptyStep, StaticRefused InHeader NoSpan (UnknownName "tip")]
        `shouldBe` ["step 3", "header"]

    it "has no location and no excerpt when the sequence was never text" $ do
      let err = StaticRefused (InStep 2 (Just "c1")) NoSpan (DuplicateName "c1")
      (sourceLocation err, excerpt "anything" err) `shouldBe` (Nothing, Nothing)

    it "names the one thing that stops a repeat, not every thing that could" $
      explain (RepeatUnmappable "folds" CountsLayers)
        `shouldBe` "\"folds\" cannot be repeated mirrored or turned: it says top N layers, and a count of layers means different paper elsewhere"

    it "says which way a range is open" $
      explain (ParameterOutOfRange 200 (Exclusive 0) (Inclusive 180))
        `shouldBe` "200° is out of range: it must be more than 0° and at most 180°"

    -- A number in a message is spelled as the printer spells it, or an author
    -- is told about a 0.58 that appears nowhere in the printed sequence.
    it "spells a number exactly, as the printer does" $
      explain (RatioOutOfRange (158 / 100)) `shouldBe` "fraction 79/50 is outside 0 to 1"

  describe "a parse problem" $ do
    it "is its hint, when it has one" $
      explain (problemAt NoSpan (FoundWord "90") ["an angle"] (Just (NeedsUnit 90)))
        `shouldBe` explain (NeedsUnit 90)

    -- These two sentences are the design's own, word for word.
    it "words a missing unit and an unclosed block as the design does" $
      map explain [NeedsUnit 90, UnclosedBlock "step half"]
        `shouldBe` ["an angle needs its unit: write 90°", "the \"{\" opening step half is never closed"]

    it "reaches a person unchanged through the error that wraps it" $ do
      let problem = problemAt NoSpan (FoundWord "fold") ["step", "closing"] Nothing
      explain (ParseFailed problem) `shouldBe` explain problem

    it "otherwise says what was found and what could have been there" $
      map
        explain
        [ problemAt NoSpan (FoundWord "fold") ["step", "closing"] Nothing,
          problemAt NoSpan (FoundChar '}') ["a move", "settle", "\"}\""] Nothing,
          problemAt NoSpan FoundEnd ["\"}\""] Nothing,
          problemAt NoSpan (FoundWord "fold") [] Nothing
        ]
        `shouldBe` [ "found \"fold\" where step or closing was expected",
                     "found \"}\" where a move, settle or \"}\" was expected",
                     "found the end of the source where \"}\" was expected",
                     "found \"fold\", which cannot come here"
                   ]

    it "names both code points for a character that only looks like the degree sign" $
      explain (problemAt NoSpan (FoundChar 'º') [] (Just (NotDegreeSign 'º')))
        `shouldBe` "\"º\" (U+00BA) is not the degree sign; write ° (U+00B0) or deg"

  describe "sourceLocation" $
    it "is path, line and column of where the error starts" $
      sourceLocation (ParseFailed (problemAt (Span "examples/w.foldseq" 7 20 7 24) (FoundWord "left") [] Nothing))
        `shouldBe` Just "examples/w.foldseq:7:20"

  -- The three outputs the design prints, on the sources it prints them for.
  describe "excerpt, on the design's three examples" $ do
    it "underlines a word" $
      excerptOf quarterFoldTyped (Span "quarter.foldseq" 7 20 7 24)
        `shouldBe` Just "  |\n7 |   fold behind edge left to edge east\n  |                    ^^^^"

    it "widens the gutter for a two-digit line number" $
      excerptOf (T.replicate 12 "\n" <> "  fold behind 90 corner north-west to midpoint of edge north\n") (Span "wing.foldseq" 13 15 13 17)
        `shouldBe` Just "   |\n13 |   fold behind 90 corner north-west to midpoint of edge north\n   |               ^^"

    it "points one caret at the brace of an unclosed block" $
      excerptOf quarterFoldTyped (Span "quarter.foldseq" 6 56 6 57)
        `shouldBe` Just "  |\n6 | step half \"Fold the left half behind, onto the right.\" {\n  |                                                        ^"

  describe "excerpt, where it is easy to get wrong" $ do
    -- A tab's width is the terminal's business. Copying it keeps the caret
    -- under the right character whatever that width is; a space would not.
    it "copies each tab of the source line into the caret line" $
      excerptOf "\tfold\tvalley edge left\n" (Span "t.foldseq" 1 19 1 23)
        `shouldBe` Just "  |\n1 | \tfold\tvalley edge left\n  | \t    \t            ^^^^"

    it "underlines a span that runs past its first line to the end of that line" $
      excerptOf "step {\n  unfold\n}\n" (Span "t.foldseq" 1 1 3 2)
        `shouldBe` Just "  |\n1 | step {\n  | ^^^^^^"

    it "draws one caret for a span with no width, and none past the end of the line" $
      map (excerptOf "fold\n") [Span "t.foldseq" 1 5 1 5, Span "t.foldseq" 1 3 1 40]
        `shouldBe` [Just "  |\n1 | fold\n  |     ^", Just "  |\n1 | fold\n  |   ^^"]

    it "shows the same line whether the file ends its lines with a carriage return or not" $
      excerptOf "fold left\r\nunfold\r\n" (Span "t.foldseq" 1 6 1 10)
        `shouldBe` excerptOf "fold left\nunfold\n" (Span "t.foldseq" 1 6 1 10)

    it "is nothing for a line the text does not have" $
      map (excerptOf "fold\n") [Span "t.foldseq" 9 1 9 2, Span "t.foldseq" 0 1 0 2]
        `shouldBe` [Nothing, Nothing]

  describe "refusalKinds" $ do
    it "lists no kind twice" $
      length (nub refusalKinds) `shouldBe` length refusalKinds

    -- The text reads a kind as a word starting with a capital, so a name that
    -- is not one could never be written after @expect refused@.
    it "holds only names a source can spell as a kind" $
      [kind | RefusalKind kind <- refusalKinds, not (spellableKind kind)] `shouldBe` []

    it "holds the kinds the design's own examples expect" $
      filter (`notElem` refusalKinds) (map RefusalKind ["FlapCovered", "FlapEndpointOrder", "ExistingHingeFlat"]) `shouldBe` []

    -- Some of the names are constructors that exist today. Reading the
    -- spelling off a real value means a renamed constructor fails here, not
    -- months later when a sequence expects a refusal that can no longer be
    -- named.
    it "spells today's constructors as the library does" $
      filter (`notElem` refusalKinds) (map RefusalKind constructorsOfToday) `shouldBe` []

    -- Turns red if a kind is given to the wrong refusal or misspelled, if a
    -- refusal named in 'noKind' were given one again or another lost its own,
    -- or if a kind given is missing from the list, which is how #580's 25
    -- came to be reported but never nameable.
    it "gives each refusal its own constructor's name as its kind, or none, and only kinds on the list" $ do
      [label | (label, named, err) <- everyRefusal, refusalKindOf err /= kindOf named] `shouldBe` []
      [label | (label, _, err) <- everyRefusal, Just kind <- [refusalKindOf err], kind `notElem` refusalKinds] `shouldBe` []

-- | The kind a refusal of this constructor has: its name, unless it is one
-- the design lets no author expect.
kindOf :: String -> Maybe RefusalKind
kindOf named
  | named `elem` noKind = Nothing
  | otherwise = Just (RefusalKind (T.pack named))

-- | The refusals with no kind: a reference or a move not run yet, the
-- runner's own creasing and a step not modelled, which had none before #580;
-- owner decision 49's 23 library refusals that are not refusals of the paper;
-- and decision 50's two expectations not met.
noKind :: [String]
noKind =
  [ "NotRunYet",
    "MoveNotRunYet",
    "CreasingRefused",
    "NotModelledStop",
    "AlreadyFolded",
    "AngleWithoutPaper",
    "DegenerateFace",
    "DisconnectedFace",
    "DuplicateEdge",
    "FaceEdgeMissing",
    "FrameGeometry",
    "NoFaces",
    "NonFiniteAngle",
    "FlapDuplicateCrease",
    "FlapEmptyHinge",
    "FlapGeometry",
    "FlapInvalidProgress",
    "FlapInvalidTravel",
    "FlapInvalidTurn",
    "FlapMissingCrease",
    "FlapMissingFace",
    "FlapMissingOwner",
    "FlapMissingVertex",
    "FlapPathMismatch",
    "FlapSurface",
    "FlapSweep",
    "FlapWrongSide",
    "RefusalNotRaised",
    "RefusedDifferently"
  ]

-- | One refusal of every constructor 'refusalKindOf' looks at, as a run
-- raises it: a label, the constructor whose name its kind must be, and the
-- refusal. A folding refusal reaches a run inside a flap's too, and there
-- takes the folding refusal's kind; and every reference's refusal reaches
-- it as a line's inside another's, once and twice over, where it keeps its
-- own kind (#570).
everyRefusal :: [(String, String, SequenceError)]
everyRefusal =
  [(named p, named p, ResolveRefused InHeader NoSpan "" p) | p <- resolveSamples]
    <> [(depth <> named p, named p, ResolveRefused InHeader NoSpan "" (wrap p)) | p <- resolveSamples, (depth, wrap) <- [("InsideLine ", InsideLine "edge east"), ("InsideLine twice ", InsideLine "edge east" . InsideLine "edge west")]]
    <> [(named e, named e, stepRefusal (Selecting e)) | e <- selectionSamples]
    <> [(named f, named f, stepRefusal f) | f <- moveSamples]
    <> [(named e, named e, stepRefusal (FlapRefused e)) | e <- flapSamples]
    <> [(named e, named e, stepRefusal (FoldingRefused e)) | e <- foldingSamples]
    <> [("FlapFolding " <> named e, named e, stepRefusal (FlapRefused (FlapFolding e))) | e <- foldingSamples]
  where
    named :: (Show a) => a -> String
    named = takeWhile isAlphaNum . show

stepRefusal :: MoveFailure -> SequenceError
stepRefusal = StepRefused 1 Nothing NoSpan

resolveSamples :: [ResolveProblem]
resolveSamples =
  [ NearMiss (0, 0) 0 (V2 0 0) 0,
    NotInOneFace (V2 0 0) 0,
    OffThePaper (V2 0 0),
    PlacementsDisagree (V2 0 0) 0,
    NoCornerThere SouthWest,
    ConstructionInTheAir 0,
    DegenerateConstruction,
    NoSolution,
    HingeOfNotOneMove "c1" 0,
    EdgeNotStraight South [],
    NeedsNearest [],
    NearestAmbiguous (V2 0 0) [],
    NearestDisagrees (V2 0 0) (CandidateLine (V2 0 0) (V2 0 1) True) OnlyOnPaper (CandidateLine (V2 0 0) (V2 1 0) False),
    NotRunYet "\"meet\""
  ]

selectionSamples :: [SelectionError]
selectionSamples = [SeedMissing, SeedOnTheLine (V2 0 0), SeedSplit (V2 0 0), SegmentStraddles (V2 0 0) (V2 1 0), NothingSelected, ExistingHingeFlat (EdgeId 0)]

-- | Every 'MoveFailure' but the three that wrap another type's refusal,
-- which are sampled by that type.
moveSamples :: [MoveFailure]
moveSamples =
  [ ReanchorNotFlat (V2 0 0) 30,
    CreasingRefused NoVertices,
    JoinBroken "",
    UnfoldChangedSince (EdgeId 0),
    MoveNotRunYet "\"turn over\"",
    NotModelledStop "an inside reverse fold",
    RefusalNotRaised (RefusalKind "NoSolution"),
    RefusedDifferently (RefusalKind "NoSolution") (RefusalKind "SeedMissing")
  ]

flapSamples :: [FlapError]
flapSamples =
  [ FlapGeometry NoVertices,
    FlapSurface (SurfaceNonConvex (FaceId 0)),
    FlapSweep InvalidSweepAxis,
    FlapMissingCrease (EdgeId 0),
    FlapNotHinge (EdgeId 0),
    FlapWrongSide (EdgeId 0) (FaceId 0),
    FlapCoupled (EdgeId 0) [],
    FlapMovingNotFlat (FaceId 0) 0,
    FlapMovesBothWays (FaceId 0) (FaceId 1),
    FlapEmptyHinge,
    FlapDuplicateCrease (EdgeId 0),
    FlapNotBoundary (EdgeId 0),
    FlapUnalignedCrease (EdgeId 0),
    FlapMissingFace (FaceId 0),
    FlapMissingOwner 0,
    FlapMissingVertex (VertexId 0),
    FlapStartMismatch,
    FlapInvalidTravel 400,
    FlapInvalidTurn 400,
    FlapInvalidProgress 2,
    FlapPathMismatch (VertexId 0),
    FlapCollision 0 [],
    FlapUnresolved 0 1 [],
    FlapEndpointOrder 0 NoVertices,
    FlapStackOrder NoVertices
  ]

foldingSamples :: [FoldingError]
foldingSamples =
  [ FrameGeometry NoVertices,
    AlreadyFolded 1,
    NoFaces,
    DegenerateFace (FaceId 0),
    FaceEdgeMissing (FaceId 0) (VertexId 0) (VertexId 1),
    DuplicateEdge (EdgeId 0) (EdgeId 1),
    DisconnectedFace (FaceId 0),
    NonFiniteAngle (EdgeId 0) (1 / 0),
    TornAt (VertexId 0) 0,
    AngleWithoutPaper (EdgeId 0) 90,
    AngleNotAchieved (EdgeId 0) 0
  ]

-- | The constructor name of each refusal in 'refusalKinds' that already
-- exists in the library, read from a real value.
constructorsOfToday :: [Text]
constructorsOfToday =
  map
    (T.takeWhile isAlphaNum . T.pack)
    [ show (FlapCoupled (EdgeId 0) [VertexId 0]),
      show (FlapNotHinge (EdgeId 0)),
      show (FlapNotBoundary (EdgeId 0)),
      show (FlapUnalignedCrease (EdgeId 0)),
      show (FlapEndpointOrder 0 NoVertices),
      show (FlapStackOrder NoVertices),
      show FlapStartMismatch,
      show (FlapMovingNotFlat (FaceId 0) 0),
      show (FlapMovesBothWays (FaceId 0) (FaceId 1)),
      show (FlapCollision 0 []),
      show (FlapUnresolved 0 1 []),
      show (TornAt (VertexId 0) 0),
      show (AngleNotAchieved (EdgeId 0) 0),
      show (LineStopsOnTheModel FromEnd (FaceId 0)),
      show (GaveUpStacking 0)
    ]

spellableKind :: Text -> Bool
spellableKind kind = case T.uncons kind of
  Just (c, rest) -> isUpper c && T.all isAlphaNum rest
  Nothing -> False

problemAt :: Span -> Found -> [Text] -> Maybe Hint -> ParseProblem
problemAt sp found expected hint =
  ParseProblem {problemSpan = sp, problemFound = found, problemExpected = expected, problemHint = hint}

-- | The excerpt of an error at this span in this source.
excerptOf :: Text -> Span -> Maybe Text
excerptOf source sp = excerpt source (ParseFailed (problemAt sp FoundEnd [] Nothing))

-- | The quarter fold as the design prints it, with @edge west@ mistyped as
-- @edge left@ on line 7. Line 6 ends in the brace the design's third example
-- points at.
quarterFoldTyped :: Text
quarterFoldTyped =
  T.unlines
    [ "foldseq 1",
      "title \"A square folded into quarters\"",
      "sheet \"examples/quarter-fold-steps.fold\"",
      "anchor (3/4, 1/4)          # south-east quarter, which neither step moves",
      "",
      "step half \"Fold the left half behind, onto the right.\" {",
      "  fold behind edge left to edge east",
      "}"
    ]

-- | Every message this module can make from a static problem or a hint, each
-- labelled with where it came from.
everyMessage :: [(String, Text)]
everyMessage =
  [("StaticProblem " <> sampledStatic p, explain p) | p <- staticSamples]
    <> [("Hint " <> sampledHint h, explain h) | h <- hintSamples]

staticSamples :: [StaticProblem]
staticSamples =
  [ UnknownName "tip",
    DuplicateName "c1",
    WrongKind "tip" LineName PointName,
    EmptyStep,
    RatioOutOfRange (3 / 2),
    NotEighths 9,
    NotQuarters 0,
    ParameterOutOfRange 200 (Exclusive 0) (Inclusive 180),
    UnknownRefusalKind (RefusalKind "FlapCoverd"),
    NestedExpectRefused (RefusalKind "NoSolution"),
    NotASingleMacro "base",
    NotAFigure "names",
    TurnsNoPaper "flipped",
    HingeOfSeveralMoves "folds",
    RepeatUnmappable "folds" UsesModelCoordinates,
    RepeatUnmappable "folds" CountsLayers,
    RepeatUnmappable "folds" IsometryByConstruction,
    RangeRunsBackwards "folds" "names",
    NotANameToken "two words",
    ReservedWordAsName "north-west",
    LayerCountNotPositive 0,
    SignNotAllowed (-90),
    UnfoldNamesNothing
  ]

hintSamples :: [Hint]
hintSamples =
  [ ViewWordForMaterial "left",
    FutureMove "squash",
    ReservedName "front",
    NeedsUnit 90,
    NotDegreeSign '˚',
    StraySign,
    ZeroDenominator,
    CountTooLarge 18446744073709551617,
    UnclosedBlock "step half",
    UnsupportedVersion 2,
    LooksLikeFold,
    FractionAlongEdge,
    DuplicateHeader "title" 2,
    HeaderAfterStep "sheet",
    NotYetSupported "a settle block",
    SpelledOtherwise "center" "centre",
    SheetMissing,
    LineOntoPoint,
    NearestWithoutTwoLines
  ]

-- | The constructor's name. Written as a match on every constructor, with no
-- catch-all, so that a constructor added to 'StaticProblem' without a sample
-- in 'staticSamples' at least warns here.
sampledStatic :: StaticProblem -> String
sampledStatic = \case
  UnknownName {} -> "UnknownName"
  DuplicateName {} -> "DuplicateName"
  WrongKind {} -> "WrongKind"
  EmptyStep -> "EmptyStep"
  RatioOutOfRange {} -> "RatioOutOfRange"
  NotEighths {} -> "NotEighths"
  NotQuarters {} -> "NotQuarters"
  ParameterOutOfRange {} -> "ParameterOutOfRange"
  UnknownRefusalKind {} -> "UnknownRefusalKind"
  NestedExpectRefused {} -> "NestedExpectRefused"
  NotASingleMacro {} -> "NotASingleMacro"
  NotAFigure {} -> "NotAFigure"
  TurnsNoPaper {} -> "TurnsNoPaper"
  HingeOfSeveralMoves {} -> "HingeOfSeveralMoves"
  RepeatUnmappable {} -> "RepeatUnmappable"
  RangeRunsBackwards {} -> "RangeRunsBackwards"
  NotANameToken {} -> "NotANameToken"
  ReservedWordAsName {} -> "ReservedWordAsName"
  LayerCountNotPositive {} -> "LayerCountNotPositive"
  SignNotAllowed {} -> "SignNotAllowed"
  UnfoldNamesNothing -> "UnfoldNamesNothing"

sampledHint :: Hint -> String
sampledHint = \case
  ViewWordForMaterial {} -> "ViewWordForMaterial"
  FutureMove {} -> "FutureMove"
  ReservedName {} -> "ReservedName"
  NeedsUnit {} -> "NeedsUnit"
  NotDegreeSign {} -> "NotDegreeSign"
  StraySign -> "StraySign"
  ZeroDenominator -> "ZeroDenominator"
  CountTooLarge {} -> "CountTooLarge"
  UnclosedBlock {} -> "UnclosedBlock"
  UnsupportedVersion {} -> "UnsupportedVersion"
  LooksLikeFold -> "LooksLikeFold"
  FractionAlongEdge -> "FractionAlongEdge"
  DuplicateHeader {} -> "DuplicateHeader"
  HeaderAfterStep {} -> "HeaderAfterStep"
  NotYetSupported {} -> "NotYetSupported"
  SpelledOtherwise {} -> "SpelledOtherwise"
  SheetMissing -> "SheetMissing"
  LineOntoPoint -> "LineOntoPoint"
  NearestWithoutTwoLines -> "NearestWithoutTwoLines"
