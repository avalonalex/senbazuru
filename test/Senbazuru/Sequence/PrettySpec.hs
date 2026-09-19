-- |
-- Tests for the printer: a fold sequence written out as text.
--
-- Three kinds, for three different jobs.
--
-- __Goldens__ for whole documents. What matters about a printed sequence is
-- whether a person would want to have written it, and that is judged by
-- reading the file, not by asserting on pieces of it. Two of the three are the
-- examples the language's design prints in full, the blintz and the quarter
-- fold, so the golden files can be laid beside the design and compared. The
-- third, @every-construct@, uses every constructor of the tree once. It folds
-- nothing sensible; it is there so that every spelling appears in a file
-- somebody has read.
--
-- __Examples__ for the rules that are easy to get subtly wrong and would be
-- easy to miss in a long golden: which numbers print unreduced, where
-- parentheses go, what is left out because the parser would supply it.
--
-- __Properties__, over random trees, for what must hold of any output at all.
-- There is no parser yet, so \"the text parses back\" cannot be tested here.
-- These are the parts of that promise which can: the output is clean text with
-- no raw control character in it, its brackets balance outside strings, and
-- the trees that are supposed to print alike do.
module Senbazuru.Sequence.PrettySpec (spec) where

import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Sequence.Pretty
import Senbazuru.Sequence.Syntax
import Test.Golden (goldenText)
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.SequenceExamples (blintz, quarterFold)
import Test.SequenceGen (genSequence)

spec :: Spec
spec = do
  describe "whole sequences" $ do
    it "prints the blintz as the design gives it, loop unrolled" $
      goldenText "test/golden/blintz.foldseq" (prettySequence blintz)

    it "prints the quarter fold as the design gives it, closing caption last" $
      goldenText "test/golden/quarter-fold.foldseq" (prettySequence quarterFold)

    it "prints every constructor of the tree" $
      goldenText "test/golden/every-construct.foldseq" (prettySequence everyConstruct)

  describe "what is left out" $ do
    it "prints only the version and the sheet for a header of defaults" $
      prettySequence (Sequence (plainHeader UnitSquare) []) `shouldBe` "foldseq 1\nsheet square\n"

    it "prints the side and the start once they are not the defaults" $
      prettySequence (Sequence (plainHeader UnitSquare) {hSide = WhiteUp, hStart = built (StartFolded StackingFirst)} [])
        `shouldBe` "foldseq 1\nsheet square\nwhite side up\nstart folded {\n  stacking first\n}\n"

    it "prints a step with no name, no caption and no moves" $
      prettySequence (Sequence (plainHeader UnitSquare) [built (Step Nothing Nothing [])])
        `shouldBe` "foldseq 1\nsheet square\n\nstep {\n}\n"

    -- A fold that goes flat prints no angle, and one told to go 180° keeps it:
    -- they are different trees, and each has to print as the text it parses
    -- from.
    it "keeps an angle of 180 degrees apart from no angle" $
      map foldAmount [ToFlat, Degrees 180]
        `shouldBe` ["fold valley edge west", "fold valley 180° edge west"]

    it "says top layer for one and counts the rest" $
      map foldLayers [FlapOfFirstArgument, TopLayers 1, TopLayers 3]
        `shouldBe` ["fold valley edge west", "fold valley edge west top layer", "fold valley edge west top 3 layers"]

  describe "numbers" $ do
    it "prints whole numbers bare and the rest in lowest terms, never as decimals" $
      map prettyPoint [AtSheet 1 0, AtSheet (58 / 100) (2 / 5), AtSheet (-1 / 2) (-3)]
        `shouldBe` ["(1, 0)", "(29/50, 2/5)", "(-1/2, -3)"]

    -- The tree stores a count of eighths or quarters, as typed, and the
    -- parser reads the denominator as written, so these two alone are not
    -- reduced.
    it "prints a turn over its own denominator, unreduced" $
      oneMove (Rotate 2 Clockwise) `shouldBe` ["rotate 2/8 turn clockwise"]

    it "prints a repeat's quarter turns unreduced too" $
      oneMove (Repeat "a" Nothing (Just (TurnedQuarters 2 Centre))) `shouldBe` ["repeat a turned 2/4 about centre"]

    it "prints an angle that is not whole as a fraction before the degree sign" $
      oneMove (Continue "base" (45 / 2)) `shouldBe` ["continue base until 45/2°"]

  describe "parentheses" $ do
    it "wraps an alignment used inside another line" $
      prettyLine (PerpendicularThrough (Onto (CornerOf SouthWest) Centre) Centre)
        `shouldBe` "perpendicular to (corner south-west to centre) through centre"

    it "wraps nothing else" $
      prettyLine (PerpendicularThrough (Segment (CornerOf SouthWest) Centre) Centre)
        `shouldBe` "perpendicular to [corner south-west, centre] through centre"

    it "wraps neither side of a line laid onto a line when both are simple" $
      prettyLine (LineOnto (EdgeOf West) (EdgeOf East) (Just Centre)) `shouldBe` "edge west to edge east nearest centre"

    it "wraps an alignment given to meet" $
      prettyPoint (Meet (PointToLine Centre (EdgeOf North)) (LineNamed "diagonal"))
        `shouldBe` "meet (centre to edge north) diagonal"

    it "leaves an alignment standing alone unwrapped" $
      prettyLine (Onto (CornerOf SouthEast) Centre) `shouldBe` "corner south-east to centre"

  describe "strings" $ do
    it "escapes a quote, a backslash, a newline and a tab" $
      oneMove (NotModelled "say \"a\\b\"\n\tthen stop") `shouldBe` ["not modelled \"say \\\"a\\\\b\\\"\\n\\tthen stop\""]

    it "writes any other control character by its code, and leaves the rest alone" $
      oneMove (NotModelled "bell\a, escape\ESC, 折り鶴 22.5°") `shouldBe` ["not modelled \"bell\\u{7}, escape\\u{1b}, 折り鶴 22.5°\""]

  describe "any output" $ do
    -- A caption holding a tab or a newline is in the generator's pool, so a
    -- raw one reaching the output means a string went out unescaped.
    prop "is clean text: no tab, no carriage return, no trailing space, one final newline" $
      forAll genSequence $ \s ->
        let out = prettySequence s
            textLines = T.lines out
         in conjoin
              [ counterexample "holds a tab or a carriage return" (not (T.any (`elem` ['\t', '\r']) out)),
                counterexample "a line ends in a space" (not (any (T.isSuffixOf " ") textLines)),
                counterexample "does not end in exactly one newline" (T.isSuffixOf "\n" out && not (T.isSuffixOf "\n\n" out)),
                counterexample "starts with something other than the version line" (take 1 textLines == ["foldseq 1"])
              ]

    prop "has its brackets balanced, outside strings" $
      forAll genSequence $ \s ->
        let out = prettySequence s
         in counterexample (T.unpack out) (bracketsBalance out)

    -- The claim "Senbazuru.Sequence.Syntax" makes for 'canonical': the trees it
    -- identifies are two spellings of one text.
    prop "is the same for a tree and its canonical form" $
      forAll genSequence $ \s ->
        prettySequence (canonical s) === prettySequence s

    prop "does not depend on where anything was written" $
      forAll genSequence $ \s ->
        prettySequence (stripSpans s) === prettySequence s

-- | A sequence using every constructor of the tree at least once, for the
-- golden that shows every spelling. \"Every\" is kept true by hand: a
-- constructor added to the tree has to be added here, and the golden read
-- again.
everyConstruct :: Sequence
everyConstruct =
  Sequence
    Header
      { hTitle = Just "Every construct, folding nothing sensible",
        hSheet = built (SheetFile "examples/crane.fold"),
        hAnchor = Just (built (AtSheet (19 / 20) (1 / 3))),
        hSide = WhiteUp,
        hStart =
          built
            ( StartFolded
                ( Relations
                    [ LayerAbove (AtSheet (1 / 4) (1 / 5)) (AtSheet (3 / 8) (5 / 9)),
                      LayerAbove (AtSheet (4 / 9) (3 / 8)) (AtSheet (1 / 4) (1 / 5))
                    ]
                )
            ),
        hClosing = Just "Done, \"more or less\"."
      }
    [ step'
        (Just "names")
        (Just "Name two points and two lines.")
        [ Mark "tip" (CornerOf NorthEast) Nothing,
          Mark "under" (MidpointOf (CornerOf SouthWest) Centre) (Just (AtSheet (1 / 8) (1 / 8))),
          Let "diagonal" (BindLine (Segment (CornerOf SouthWest) (CornerOf NorthEast))),
          Let "third" (BindPoint (FractionAlong (1 / 3) (CornerOf SouthWest) (CornerOf SouthEast)))
        ],
      step'
        (Just "folds")
        (Just "Every way of naming a fold line.")
        [ Fold ValleyFold ToFlat (Onto (CornerOf SouthEast) Centre) FlapOfFirstArgument Nothing,
          Fold MountainFold (Degrees 90) (LineOnto (EdgeOf West) (EdgeOf East) (Just Centre)) AllLayers (Just (PointNamed "tip")),
          Fold ValleyFold (Degrees (45 / 2)) (PerpendicularThrough (Onto (CornerOf SouthWest) Centre) Centre) (TopLayers 1) Nothing,
          Fold ValleyFold ToFlat (PointToLineThrough (CornerOf NorthWest) (EdgeOf South) (MidpointOfEdge North) (Just (CornerOf NorthEast))) (TopLayers 3) Nothing,
          Fold ValleyFold ToFlat (TwoToTwo (PointNamed "tip") (EdgeOf South) (PointNamed "third") (LineNamed "diagonal") Nothing) TopFlap Nothing,
          Fold MountainFold ToFlat (PointToLinePerpendicular Centre (EdgeOf East) (EdgeOf North)) FlapOfFirstArgument Nothing,
          Fold ValleyFold ToFlat (PointToLine (CornerOf NorthEast) (ExistingCrease (CornerOf SouthWest) Centre)) FlapOfFirstArgument Nothing,
          Fold ValleyFold ToFlat (ModelSegment (-1 / 2, 0) (3, 1 / 4)) FlapOfFirstArgument (Just (Meet (HingeOf "names") (CreaseOf "names"))),
          Fold ValleyFold ToFlat (Segment (PointNamed "under") Centre) FlapOfFirstArgument (Just (EndOfCreaseOf "names" Centre)),
          FoldAndUnfold ValleyFold (LineNamed "diagonal") FlapOfFirstArgument (Just (CornerOf NorthWest))
        ],
      step'
        Nothing
        Nothing
        [ TurnOver LeftRight,
          TurnOver TopBottom,
          Rotate 1 Anticlockwise,
          Rotate 2 Clockwise,
          Anchor Centre
        ],
      step'
        (Just "base")
        (Just "The macro-moves.")
        [ Macro (Collapse Centre (Just (CornerOf SouthWest, CornerOf NorthEast)) 180) [30, 60, 90],
          Macro (Collapse Centre Nothing 90) [],
          Macro (RabbitEar (CornerOf NorthWest) 90) [],
          Macro (Petal (TipAt (CornerOf SouthEast)) 175) [],
          Macro (Petal TopFlapTip 175) []
        ],
      step'
        Nothing
        (Just "Blocks inside a step.")
        [ Together [built (Continue "base" 180), built (Continue "folds" 180)],
          Pose [(Centre, CornerOf NorthWest, -90), (Centre, CornerOf SouthEast, 45 / 2)],
          Unfold ["names", "folds"]
        ],
      step'
        Nothing
        (Just "Everything else.")
        [ Repeat "names" Nothing Nothing,
          Repeat "names" (Just "folds") (Just (MirroredAcross (CornerOf SouthWest) (CornerOf NorthEast))),
          Repeat "base" Nothing (Just (TurnedQuarters 2 Centre)),
          Checkpoint "crane.fold" StackingFirst,
          Checkpoint "half.fold" (Relations [LayerAbove (PointNamed "tip") Centre]),
          NotModelled "inside reverse fold",
          ExpectRefused (RefusalKind "FlapCovered") (Fold ValleyFold (Degrees 90) (Onto (CornerOf NorthWest) (MidpointOfEdge North)) FlapOfFirstArgument Nothing)
        ]
    ]
  where
    step' name caption moves = built (Step name caption (map built moves))

built :: a -> Located a
built = Located NoSpan

plainHeader :: SheetSource -> Header
plainHeader sheet =
  Header
    { hTitle = Nothing,
      hSheet = built sheet,
      hAnchor = Nothing,
      hSide = ColouredUp,
      hStart = built StartFlat,
      hClosing = Nothing
    }

-- | The lines one move prints as, without the step around it.
oneMove :: Move -> [Text]
oneMove m =
  map (T.drop 2)
    . takeWhile (/= "}")
    . drop 1
    . dropWhile (/= "step {")
    . T.lines
    $ prettySequence (Sequence (plainHeader UnitSquare) [built (Step Nothing Nothing [built m])])

foldAmount :: Amount -> Text
foldAmount amount = T.unwords (oneMove (Fold ValleyFold amount (EdgeOf West) FlapOfFirstArgument Nothing))

foldLayers :: Layers -> Text
foldLayers layers = T.unwords (oneMove (Fold ValleyFold ToFlat (EdgeOf West) layers Nothing))

-- | Whether every bracket closes the one most recently opened, ignoring
-- whatever is inside a string. A backslash inside a string skips the character
-- after it, so an escaped quote does not end the string.
bracketsBalance :: Text -> Bool
bracketsBalance = go [] . T.unpack
  where
    go open = \case
      [] -> null open
      '"' : rest -> go open (afterString rest)
      c : rest
        | c `elem` ("([{" :: String) -> go (c : open) rest
        | c `elem` (")]}" :: String) -> case open of
            o : others | closes o c -> go others rest
            _ -> False
        | otherwise -> go open rest

    afterString = \case
      [] -> []
      '\\' : _ : rest -> afterString rest
      '"' : rest -> rest
      _ : rest -> afterString rest

    closes o c = (o, c) `elem` [('(', ')'), ('[', ']'), ('{', '}')]
