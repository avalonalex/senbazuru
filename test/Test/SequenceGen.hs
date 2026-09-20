-- |
-- Module      : Test.SequenceGen
-- Description : Random fold sequences, for every spec that needs one.
--
-- One generator, shared, because the properties worth stating about a
-- 'Sequence' are all of the form \"for every sequence\": normalising it twice
-- changes nothing, printing it gives text that parses back. A generator per
-- spec would mean each spec quietly covering a different subset of the tree.
--
-- == What it is careful about
--
-- It produces only values a sequence source could /spell/. Names are words a
-- source may use as names; a fold's angle is never negative, because text
-- allows a minus sign only in coordinates and in a pose; a turn is one to
-- seven eighths. The tree's types allow more than that — a 'Name' can hold any
-- text — and a value no source can spell has no text to print or parse, so it
-- belongs to the tests of the checker that refuses it.
--
-- == What it is not careful about
--
-- Spellable is not the same as /meaningful/. A name is drawn from a small
-- pool with no regard to what defines it, so most generated sequences unfold
-- a step that does not exist or define one name twice, and a checker would
-- refuse them. Nothing tested so far looks a name up, so nothing so far
-- minds. A property that holds only for sequences a checker accepts will
-- need a generator that defines each name before using it; this one would
-- have nearly every case thrown away.
--
-- It makes bare names common on purpose. The only interesting thing
-- 'Senbazuru.Sequence.Syntax.canonical' does happens at a line that is just a
-- name, and a generator that picked uniformly among fourteen kinds of line
-- would reach that case too rarely to test it.
--
-- Depth is bounded by hand, not by QuickCheck's size, because points hold
-- lines and lines hold points: left to itself that recursion produces trees
-- too large to read in a failure report long before it produces a new case.
module Test.SequenceGen
  ( genSequence,
    genSequenceWith,
    genSpan,
    genLine,
    genPoint,
    genMove,
    namePool,
    kindPool,
  )
where

import Data.Ratio ((%))
import Data.Text (Text)
import Senbazuru.Sequence.Syntax
import Test.QuickCheck

-- | A sequence whose spans are a mixture of real positions and 'NoSpan'.
genSequence :: Gen Sequence
genSequence = genSequenceWith genSpan

-- | A sequence whose every span comes from the given generator, so that a
-- spec can ask for one with no positions at all: @genSequenceWith (pure NoSpan)@.
genSequenceWith :: Gen Span -> Gen Sequence
genSequenceWith spans = Sequence <$> genHeader spans <*> short (located spans (genStep spans))

-- | 'NoSpan', or a span that ends at or after the place it starts, as every
-- span a parser makes does.
genSpan :: Gen Span
genSpan = frequency [(1, pure NoSpan), (3, realSpan)]
  where
    realSpan = do
      path <- elements ["a.foldseq", "examples/b.foldseq"]
      startLine <- choose (1, 400)
      startColumn <- choose (1, 120)
      endLine <- choose (startLine, startLine + 12)
      endColumn <- choose (if endLine == startLine then startColumn else 1, 120)
      pure (Span path startLine startColumn endLine endColumn)

located :: Gen Span -> Gen a -> Gen (Located a)
located spans value = Located <$> spans <*> value

genHeader :: Gen Span -> Gen Header
genHeader spans =
  Header
    <$> optional genCaption
    <*> located spans genSheet
    <*> optional (located spans (genPoint 2))
    <*> arbitraryBoundedEnum
    <*> located spans genStart
    <*> optional genCaption
  where
    genSheet = oneof [pure UnitSquare, SheetFile <$> genPath]
    genStart = oneof [pure StartFlat, StartFolded <$> genSpec]

genStep :: Gen Span -> Gen Step
genStep spans = Step <$> optional genName <*> optional genCaption <*> short (located spans (genMove spans 2))

-- | A move. The depth bounds how far @together@ and @expect refused@ nest.
genMove :: Gen Span -> Int -> Gen Move
genMove spans depth =
  frequency ([(8, fold), (2, foldAndUnfold)] <> map (1,) (flatMoves <> nestedMoves))
  where
    fold = Fold <$> arbitraryBoundedEnum <*> genAmount <*> genLine 2 <*> genLayers <*> optional (genPoint 1)
    foldAndUnfold = FoldAndUnfold <$> arbitraryBoundedEnum <*> genLine 2 <*> genLayers <*> optional (genPoint 1)
    flatMoves =
      [ Unfold <$> listOf1 genName,
        TurnOver <$> arbitraryBoundedEnum,
        Rotate <$> choose (1, 7) <*> arbitraryBoundedEnum,
        Anchor <$> genPoint 2,
        Mark <$> genName <*> genPoint 2 <*> optional (genPoint 1),
        Let <$> genName <*> oneof [BindPoint <$> genPoint 2, BindLine <$> genLine 2],
        Macro <$> genMacro <*> short genAngle,
        Continue <$> genName <*> genAngle,
        Pose <$> listOf1 ((,,) <$> genPoint 1 <*> genPoint 1 <*> genSigned),
        Repeat <$> genName <*> optional genName <*> optional genIsometry,
        Checkpoint <$> genPath <*> genSpec,
        NotModelled <$> genCaption
      ]
    nestedMoves
      | depth <= 0 = []
      | otherwise =
          [ Together <$> short (located spans (genMove spans (depth - 1))),
            ExpectRefused . RefusalKind <$> elements kindPool <*> genMove spans (depth - 1)
          ]

genMacro :: Gen MacroCall
genMacro =
  oneof
    [ Collapse <$> genPoint 1 <*> optional ((,) <$> genPoint 1 <*> genPoint 1) <*> genAngle,
      RabbitEar <$> genPoint 1 <*> genAngle,
      Petal <$> oneof [TipAt <$> genPoint 1, pure TopFlapTip] <*> genAngle
    ]

genIsometry :: Gen Isometry
genIsometry =
  oneof
    [ MirroredAcross <$> genPoint 1 <*> genPoint 1,
      TurnedQuarters <$> choose (1, 3) <*> genPoint 1
    ]

genSpec :: Gen StackingSpec
genSpec = oneof [pure StackingFirst, Relations <$> listOf1 (LayerAbove <$> genPoint 1 <*> genPoint 1)]

genLayers :: Gen Layers
genLayers = oneof [pure FlapOfFirstArgument, pure AllLayers, TopLayers <$> choose (1, 4), pure TopFlap]

genAmount :: Gen Amount
genAmount = oneof [pure ToFlat, Degrees <$> genAngle]

-- | A point, nesting other points and lines at most this deep.
genPoint :: Int -> Gen Point
genPoint depth = frequency (leaves <> if depth <= 0 then [] else nodes)
  where
    leaves =
      [ (3, PointNamed <$> genName),
        (2, CornerOf <$> arbitraryBoundedEnum),
        (1, pure Centre),
        (1, AtSheet <$> genSigned <*> genSigned),
        (1, MidpointOfEdge <$> arbitraryBoundedEnum)
      ]
    nodes =
      [ (1, MidpointOf <$> smaller <*> smaller),
        (1, FractionAlong <$> genFraction <*> smaller <*> smaller),
        (1, Meet <$> smallerLine <*> smallerLine),
        (1, EndOfCreaseOf <$> genName <*> smaller)
      ]
    smaller = genPoint (depth - 1)
    smallerLine = genLine (depth - 1)

-- | A line, nesting other lines and points at most this deep.
genLine :: Int -> Gen Line
genLine depth = frequency (leaves <> if depth <= 0 then [] else nodes)
  where
    leaves =
      [ (4, LineNamed <$> genName),
        (2, EdgeOf <$> arbitraryBoundedEnum),
        (1, HingeOf <$> genName),
        (1, CreaseOf <$> genName),
        (1, ModelSegment <$> ((,) <$> genSigned <*> genSigned) <*> ((,) <$> genSigned <*> genSigned))
      ]
    nodes =
      [ (1, Segment <$> point <*> point),
        (2, Onto <$> point <*> point),
        (3, LineOnto <$> line <*> line <*> optional point),
        (1, PerpendicularThrough <$> line <*> point),
        (1, PointToLineThrough <$> point <*> line <*> point <*> optional point),
        (1, TwoToTwo <$> point <*> line <*> point <*> line <*> optional point),
        (1, PointToLinePerpendicular <$> point <*> line <*> line),
        (3, PointToLine <$> point <*> line),
        (1, ExistingCrease <$> point <*> point),
        -- The shapes 'canonical' rewrites, asked for by name. Left to the
        -- rows above, a bare name lands in the right operand so rarely that
        -- only 9% of 400 generated sequences held anything to rewrite.
        (4, PointToLine <$> point <*> bareName),
        (4, LineOnto <$> bareName <*> line <*> pure Nothing)
      ]
    point = genPoint (depth - 1)
    line = genLine (depth - 1)
    bareName = LineNamed <$> genName

-- | Words a sequence source may use as names: a letter, then letters, digits,
-- @-@ and @_@, and none of them reserved. @first-petal@ is here because it
-- starts with a reserved word and is still a name.
genName :: Gen Name
genName = Name <$> elements namePool

-- | The names the generator draws from, for a spec that has to tell a
-- sequence's own words from the language's.
namePool :: [Text]
namePool = ["a", "b", "c1", "flap-2", "first-petal", "wing_tip", "L", "P"]

-- | The kinds of refusal the generator draws from.
kindPool :: [Text]
kindPool = ["ExistingHingeFlat", "UnknownName"]

-- | Captions, including the ones a printer has to escape. The last has two
-- control characters with no letter of their own, a bell and an escape, which
-- a printer has to write by their codes.
genCaption :: Gen Text
genCaption =
  elements
    [ "",
      "Fold the south-east corner behind, to the centre.",
      "Say \"valley\", then unfold.",
      "back\\slash",
      "two\nlines",
      "tab\there",
      "折り鶴 — 22.5°",
      "bell\a and escape\ESC"
    ]

genPath :: Gen FilePath
genPath = elements ["sheet.fold", "examples/crane.fold", "/abs/base.fold"]

-- | A number where text allows a minus sign.
genSigned :: Gen Rational
genSigned = (%) <$> choose (-24, 24) <*> choose (1, 16)

-- | An angle in degrees where text allows no sign.
genAngle :: Gen Rational
genAngle = (%) <$> choose (0, 720) <*> elements [1, 2, 4]

-- | A fraction of the way along a segment.
genFraction :: Gen Rational
genFraction = do
  denominator <- choose (1, 16)
  numerator <- choose (0, denominator)
  pure (numerator % denominator)

optional :: Gen a -> Gen (Maybe a)
optional value = oneof [pure Nothing, Just <$> value]

-- | At most three, so that a failure report stays readable.
short :: Gen a -> Gen [a]
short value = do
  n <- choose (0, 3)
  vectorOf n value
