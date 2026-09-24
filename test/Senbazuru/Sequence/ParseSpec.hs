-- |
-- Tests for the text parser, and the first tests of the promise the whole
-- sequence language is built round: a sequence written in Haskell and the same
-- one written as text are the same value, and a printed sequence parses back.
--
-- __The round trip__ is a property over random trees: print one, parse the
-- text, strip the positions, and the tree comes back, in its canonical form.
-- It is the test that finds what nobody thought to write down, a spelling the
-- printer emits and the parser reads differently. It runs over every tree a
-- source can spell, meaningful or not, which is more than the design asks
-- for. The design's own form, for sequences the checker accepts, is in the
-- checker's spec, stated more strongly there and with the reason.
--
-- __Built equals parsed__, on the two examples the design works through. The
-- blintz is read from @blintz.foldseq@ at the repository root, typed as an
-- author would type it, with @behind@ for @mountain@ and a comment, and has to
-- equal the Haskell blintz, loop and all. Then every row of the builder's
-- vocabulary is compared with the parse of its own text, so that a builder's
-- default cannot drift from the parser's.
--
-- __Mistakes__ are matched on the 'Hint' and the place, never on the words. A
-- hint is data so that this is possible: the sentence can be improved without
-- a test noticing, and a test can say /which/ mistake it expects.
module Senbazuru.Sequence.ParseSpec (spec) where

import Control.Monad (void)
import Data.Char (isAlpha, isAlphaNum)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Parse
import Senbazuru.Sequence.Pretty (prettySequence)
import Senbazuru.Sequence.Syntax
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.SequenceExamples (blintz, quarterFold)
import Test.SequenceGen (genSequence, kindPool, namePool)
import Test.SequenceHelpers (built, plainHeader)

spec :: Spec
spec = do
  describe "print, then parse" $ do
    -- 'checkCoverage' makes the property fail if the generator stops reaching
    -- the nested cases, which are where a missing pair of parentheses hides.
    prop "gives the sequence back, in its canonical form" $
      checkCoverage $
        forAll genSequence $ \s ->
          cover 20 (canonical s /= s) "held a shape canonical rewrites" $
            counterexample (T.unpack (prettySequence s)) $
              fmap stripSpans (parseSequence "gen" (prettySequence s)) === Right (canonical (stripSpans s))

    it "reads each golden of the printer back into text identical to it" $
      mapM_
        ( \path -> do
            text <- TIO.readFile path
            fmap prettySequence (parseSequence path text) `shouldBe` Right text
        )
        ["test/golden/blintz.foldseq", "test/golden/quarter-fold.foldseq", "test/golden/every-construct.foldseq"]

    -- Every word the printer writes outside a string has to be one the parser
    -- knows, or a name the sequence itself uses.
    prop "prints no word that is neither reserved nor one of the sequence's own" $
      forAll genSequence $ \s ->
        let known = Set.union reservedWords (ownWords s)
         in filter (`Set.notMember` known) (wordsOutsideStrings (prettySequence s)) === []

  describe "built equals parsed" $ do
    it "reads the blintz at the repository root as the Haskell blintz" $ do
      text <- TIO.readFile "blintz.foldseq"
      fmap stripSpans (parseSequence "blintz.foldseq" text) `shouldBe` Right blintz

    it "reads the quarter fold as typed, aliases and comment and all" $ do
      text <- TIO.readFile "test/fixtures/quarter-fold.foldseq"
      fmap stripSpans (parseSequence "quarter-fold.foldseq" text) `shouldBe` Right quarterFold

    it "gives each row of the builder's vocabulary the tree its builder gives" $
      mapM_
        (\(text, body) -> (text, oneStep text) `shouldBe` (text, Right (movesOf body)))
        [ ("fold valley corner south-east to centre", fold valley (cornerOf SouthEast `onto` centre)),
          ("fold behind 90° corner south-east to centre top flap moving corner south-east", move (Fold mountain (Degrees 90) (cornerOf SouthEast `onto` centre) topFlap (Just (cornerOf SouthEast)))),
          ("pre-crease valley corner south-east to centre", preCrease valley (cornerOf SouthEast `onto` centre)),
          ("turn over left-right", turnOver LeftRight),
          ("rotate 1/8 turn anticlockwise", rotate 1 Anticlockwise),
          ("mark A = centre", void (mark "A" centre Nothing)),
          ("let L = corner south-east to centre", void (letLine "L" (cornerOf SouthEast `onto` centre))),
          ("expect refused ExistingHingeFlat { fold valley edge west to edge east }", expectRefused (RefusalKind "ExistingHingeFlat") (Fold valley ToFlat (LineOnto (edge West) (edge East) Nothing) FlapOfFirstArgument Nothing)),
          ("not modelled \"inside reverse fold\"", notModelled "inside reverse fold")
        ]

    it "reads a header of the required lines alone as the builder's header" $
      fmap (seqHeader . stripSpans) (parseSequence "t" "foldseq 1\ntitle \"T\"\nsheet square\nanchor (3/4, 1/4)\n")
        `shouldBe` Right (header "T" sheetSquare (Just (at (3 / 4) (1 / 4))))

    it "reads a step with no caption as one, and an empty caption as another" $
      fmap (map (stepCaption . locValue) . seqSteps) (parseSequence "t" "foldseq 1\nsheet square\nstep { turn over left-right }\nstep \"\" { turn over left-right }\n")
        `shouldBe` Right [Nothing, Just ""]

  describe "the text's other spellings" $ do
    it "reads in front and behind as the two senses" $
      map oneStep ["fold in front edge west", "fold behind edge west"]
        `shouldBe` map oneStep ["fold valley edge west", "fold mountain edge west"]

    it "reads precrease, fold and unfold, deg, flap containing and top 1 layers as their canonical forms" $
      oneStep "precrease valley edge west top 1 layers flap containing centre; fold and unfold valley edge west; fold valley 90deg edge west"
        `shouldBe` oneStep "pre-crease valley edge west top layer moving centre; pre-crease valley edge west; fold valley 90° edge west"

    it "keeps a decimal exact" $
      oneStep "anchor (0.58, 0.4)" `shouldBe` Right [Anchor (AtSheet (29 / 50) (2 / 5))]

    -- The tree stores the count of eighths as typed, so 2/8 is not a quarter.
    it "keeps a turn's count as typed" $
      oneStep "rotate 2/8 turn clockwise" `shouldBe` Right [Rotate 2 Clockwise]

    it "reads every escape a string can hold" $
      oneStep "not modelled \"say \\\"a\\\\b\\\"\\n\\tbell\\u{7}\"" `shouldBe` Right [NotModelled "say \"a\\b\"\n\tbell\a"]

    -- U+D800 is a surrogate: a code, and no character. Text would swap it for
    -- U+FFFD without a word, so it is refused, at the digits.
    it "refuses the code of no character" $ do
      locationOf (inStep "not modelled \"x\\u{D800}y\"") `shouldBe` Just "t:4:21"
      fmap problemFound (problemOf (inStep "not modelled \"x\\u{D800}y\"")) `shouldBe` Just (FoundWord "D800")
      locationOf (inStep "not modelled \"x\\u{110000}y\"") `shouldBe` Just "t:4:21"
      oneStep "not modelled \"\\u{D7FF}\\u{E000}\\u{10FFFF}\"" `shouldBe` Right [NotModelled "\xD7FF\xE000\x10FFFF"]

  describe "layout" $ do
    it "ignores comments, blank lines and indentation, and takes ; for a new line" $
      fmap stripSpans (parseSequence "t" "foldseq 1   # the version\nsheet square\n\n\n   # a comment alone\nstep a {\n\t\tturn over left-right ; turn over top-bottom # two on a line\n\n}\n")
        `shouldBe` Right (Sequence (plainHeader UnitSquare) [built (Step (Just "a") Nothing [built (TurnOver LeftRight), built (TurnOver TopBottom)])])

    -- Inside brackets a newline is only a space, so a long construction can
    -- wrap. Everywhere else it ends the statement.
    it "lets a line wrap inside brackets, and nowhere else" $ do
      oneStep "fold valley [corner south-west,\n      corner north-east\n  ] moving (1/4,\n 3/4)"
        `shouldBe` Right [Fold ValleyFold ToFlat (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (AtSheet (1 / 4) (3 / 4)))]
      -- Refused where the first line ends, for having ended there.
      fmap (\p -> (problemFound p, sourceLocation (ParseFailed p))) (problemOf (inStep "fold valley\n edge west"))
        `shouldBe` Just (FoundLineEnd, Just "t:4:14")

    -- 'anchor' reads a point and 'fold' reads a point or a line, by different
    -- routes. Both have to let the same things stand after the bracket.
    it "lets a comment stand inside brackets wherever a new line can" $
      oneStep "anchor ( # half\n 1/2, 1/2); fold valley ( # half\n 1/2, 1/2) to centre"
        `shouldBe` Right [Anchor (AtSheet (1 / 2) (1 / 2)), Fold ValleyFold ToFlat (Onto (AtSheet (1 / 2) (1 / 2)) Centre) FlapOfFirstArgument Nothing]

    it "reads a file with Windows line ends the same" $
      fmap stripSpans (parseSequence "t" "foldseq 1\r\nsheet square\r\nstep { turn over left-right }\r\n")
        `shouldBe` fmap stripSpans (parseSequence "t" "foldseq 1\nsheet square\nstep { turn over left-right }\n")

    it "takes header lines in any order" $
      fmap (seqHeader . stripSpans) (parseSequence "t" "foldseq 1\nwhite side up\nanchor centre\nsheet square\ntitle \"T\"\n")
        `shouldBe` Right ((header "T" sheetSquare (Just centre)) {hSide = WhiteUp})

  describe "a bare name beside to" $ do
    it "is read as a point, whatever it turns out to name" $
      oneStep "fold valley a to b" `shouldBe` Right [Fold ValleyFold ToFlat (Onto (PointNamed "a") (PointNamed "b")) FlapOfFirstArgument Nothing]

    it "is read as a line once another word says so" $
      oneStep "fold valley a to b nearest centre; fold valley a to b through c"
        `shouldBe` Right
          [ Fold ValleyFold ToFlat (LineOnto (LineNamed "a") (LineNamed "b") (Just Centre)) FlapOfFirstArgument Nothing,
            Fold ValleyFold ToFlat (PointToLineThrough (PointNamed "a") (LineNamed "b") (PointNamed "c") Nothing) FlapOfFirstArgument Nothing
          ]

    it "is read as a line after a line, since a line is never laid onto a point" $
      oneStep "fold valley edge west to b" `shouldBe` Right [Fold ValleyFold ToFlat (LineOnto (EdgeOf West) (LineNamed "b") Nothing) FlapOfFirstArgument Nothing]

    it "comes out canonical even through parentheses" $
      oneStep "let n = (b)" `shouldBe` Right [Let "n" (BindPoint (PointNamed "b"))]

  describe "spans" $ do
    it "run from a move's first character to its last, not into the comment after it" $
      fmap (map locSpan . concatMap (stepMoves . locValue) . seqSteps) (parseSequence "q.foldseq" "foldseq 1\nsheet square\nstep {\n  fold behind edge west to edge east   # the left half\n}\n")
        `shouldBe` Right [Span "q.foldseq" 4 3 4 37]

    it "cover a whole step, and each refusable header line" $ do
      let parsed = parseSequence "q.foldseq" "foldseq 1\nsheet \"a.fold\"\nanchor centre\nstep half \"H\" {\n  turn over left-right\n}\n"
      fmap (map locSpan . seqSteps) parsed `shouldBe` Right [Span "q.foldseq" 4 1 6 2]
      fmap (locSpan . hSheet . seqHeader) parsed `shouldBe` Right (Span "q.foldseq" 2 1 2 15)
      fmap (fmap locSpan . hAnchor . seqHeader) parsed `shouldBe` Right (Just (Span "q.foldseq" 3 1 3 14))

  describe "a mistake with a name" $ do
    it "is a word for what the reader sees, where paper is named" $ do
      text <- TIO.readFile "test/fixtures/quarter-fold.foldseq"
      mistakeIn "quarter.foldseq" (T.replace "edge west to" "edge left to" text) `shouldBe` Just (ViewWordForMaterial "left", "quarter.foldseq:7:20")
      mistake (inStep "fold valley corner top-left to centre") `shouldBe` Just (ViewWordForMaterial "top-left", "t:4:22")

    -- Only whole words are reserved. A name that merely starts with one, or
    -- is made of them, is a name anywhere a name can stand; it is only after
    -- @corner@ or @edge@, where no name can come, that @top-left@ is a mistake.
    it "is not a name that merely starts with a reserved word" $
      oneStep "mark top-left = centre; mark left-ear = centre; anchor first-petal"
        `shouldBe` Right [Mark "top-left" Centre Nothing, Mark "left-ear" Centre Nothing, Anchor (PointNamed "first-petal")]

    -- @90degrees@ is a number with no unit, pointed at as one: the unit is the
    -- whole word @deg@ or nothing, and a failure at the @r@ would help nobody.
    it "is an angle with no unit, or with a look-alike of the degree sign" $ do
      mistake (inStep "fold behind 90 corner north-west to centre") `shouldBe` Just (NeedsUnit 90, "t:4:15")
      mistake (inStep "fold behind 90degrees corner north-west to centre") `shouldBe` Just (NeedsUnit 90, "t:4:15")
      mistake (inStep "fold behind 90º corner north-west to centre") `shouldBe` Just (NotDegreeSign 'º', "t:4:17")

    it "is a block that is never closed, pointed at where it opens" $ do
      text <- TIO.readFile "test/fixtures/quarter-fold.foldseq"
      mistakeIn "quarter.foldseq" (T.unlines (take 7 (T.lines text))) `shouldBe` Just (UnclosedBlock "step half", "quarter.foldseq:6:56")

    it "is a number no fraction can hold, or a sign where none is allowed" $ do
      mistake (inStep "anchor (1/0, 0)") `shouldBe` Just (ZeroDenominator, "t:4:11")
      mistake (inStep "fold valley -90° edge west") `shouldBe` Just (StraySign, "t:4:15")

    -- 2^64 + 1, which narrowed to a machine integer is 1. Every whole number
    -- the tree keeps has to refuse it, and the version has to name it whole.
    it "is a count too large to hold, which would otherwise wrap round to a small one" $ do
      mistake (inStep "fold valley edge west top 18446744073709551617 layers") `shouldBe` Just (CountTooLarge 18446744073709551617, "t:4:29")
      mistake (inStep "rotate 18446744073709551617/8 turn clockwise") `shouldBe` Just (CountTooLarge 18446744073709551617, "t:4:10")
      mistake (inStep "repeat a turned 18446744073709551617/4 about centre") `shouldBe` Just (CountTooLarge 18446744073709551617, "t:4:19")
      mistake "foldseq 18446744073709551617\nsheet square\n" `shouldBe` Just (UnsupportedVersion 18446744073709551617, "t:1:9")

    it "is a reserved word used as a name" $ do
      mistake "foldseq 1\nsheet square\nstep front { turn over left-right }\n" `shouldBe` Just (ReservedName "front", "t:3:6")
      mistake (inStep "mark North-West = centre") `shouldBe` Just (ReservedName "North-West", "t:4:8")

    it "is any reserved word at all used as a name, in either case" $
      mapM_
        (\word -> mistake (inStep ("mark " <> word <> " = centre")) `shouldBe` Just (ReservedName word, "t:4:8"))
        (concatMap (\word -> [word, T.toUpper word]) (Set.toList reservedWords))

    -- The property above, that the printer writes only reserved words, would
    -- notice a printed keyword dropped from the list. These are the keywords
    -- it cannot see, because the printer never writes them.
    it "reserves the spellings only an author writes" $
      filter (`Set.notMember` reservedWords) ["coloured", "material", "settle", "precrease", "front", "behind"] `shouldBe` []

    it "is a move the language cannot express yet, or a block it does not run yet" $ do
      mistake (inStep "squash corner south-east") `shouldBe` Just (FutureMove "squash", "t:4:3")
      mistake (inStep "settle { refine side moving 3 }") `shouldBe` Just (NotYetSupported "a settle block", "t:4:3")
      mistake "foldseq 1\nsheet square\nmaterial { stiffness illustrative }\n" `shouldBe` Just (NotYetSupported "a material block", "t:3:1")

    it "is a word spelled the other way" $ do
      mistake (inStep "anchor center") `shouldBe` Just (SpelledOtherwise "center" "centre", "t:4:10")
      mistake (inStep "rotate 1/8 turn counterclockwise") `shouldBe` Just (SpelledOtherwise "counterclockwise" "anticlockwise", "t:4:19")

    it "is a header line twice, after a step, or the one that must be there and is not" $ do
      mistake "foldseq 1\nsheet square\ntitle \"A\"\ntitle \"B\"\n" `shouldBe` Just (DuplicateHeader "title" 3, "t:4:1")
      mistake "foldseq 1\nwhite side up\ncoloured side up\nsheet square\n" `shouldBe` Just (DuplicateHeader "side" 2, "t:3:1")
      -- The line is remembered as @side@ and underlined as written, all eight
      -- letters of @coloured@.
      fmap problemSpan (problemOf "foldseq 1\nwhite side up\ncoloured side up\nsheet square\n") `shouldBe` Just (Span "t" 3 1 3 9)
      mistake "foldseq 1\nsheet square\nstep { turn over left-right }\nanchor centre\n" `shouldBe` Just (HeaderAfterStep "anchor", "t:4:1")
      mistake "foldseq 1\ntitle \"No paper\"\n" `shouldBe` Just (SheetMissing, "t:1:1")

    it "is a fraction along an edge, which has no first end" $
      mistake (inStep "anchor fraction 1/3 along edge north") `shouldBe` Just (FractionAlongEdge, "t:4:29")

    it "is the wrong first line" $ do
      mistake "foldseq 2\nsheet square\n" `shouldBe` Just (UnsupportedVersion 2, "t:1:9")
      mistake "{\"file_spec\": 1.1}" `shouldBe` Just (LooksLikeFold, "t:1:1")

  describe "a mistake without one" $ do
    it "says what was found, read whole, and what could have been there" $
      fmap (\p -> (problemFound p, problemExpected p)) (problemOf (inStep "fold sideways edge west"))
        `shouldBe` Just (FoundWord "sideways", ["\"and\"", "valley or mountain"])

    -- Both of these point /back/ at text already read, which is the case the
    -- parser's alignment function is laid out to keep: a refusal that points
    -- back loses to any failure further along, unless it is raised alone.
    it "refuses a line laid onto a point, pointing at the point" $
      mistake (inStep "fold valley edge west to corner north-east") `shouldBe` Just (LineOntoPoint, "t:4:28")

    -- Text inside brackets can wrap, so what a refusal is about can end on a
    -- later line than it starts on, and the span has to say so.
    it "gives a refusal about wrapped text a span that ends on the line it ends on" $
      fmap (errorSpan . ParseFailed) (problemOf (inStep "fold valley edge west to midpoint of [corner south-west,\n corner north-east]"))
        `shouldBe` Just (Span "t" 4 28 5 20)

    it "refuses nearest where there is only one way to make the fold" $ do
      mistake (inStep "fold valley corner south-west to centre nearest centre") `shouldBe` Just (NearestWithoutTwoLines, "t:4:43")
      -- A bare name may yet be a line, so this one is allowed.
      oneStep "fold valley a to edge north nearest centre"
        `shouldBe` Right [Fold ValleyFold ToFlat (LineOnto (LineNamed "a") (EdgeOf North) (Just Centre)) FlapOfFirstArgument Nothing]

    it "asks for a point where a line stands first before through" $ do
      fmap problemExpected (problemOf (inStep "fold valley edge west to edge east through centre")) `shouldBe` Just ["a point"]
      locationOf (inStep "fold valley edge west to edge east through centre") `shouldBe` Just "t:4:15"

    it "asks for eighths after rotate" $
      fmap (\p -> (problemFound p, problemExpected p)) (problemOf (inStep "rotate 1/4 turn clockwise"))
        `shouldBe` Just (FoundChar '/', ["\"/8\"", "a digit"])

    it "refuses a move outside a step, and anything before the first line" $ do
      fmap problemFound (problemOf "foldseq 1\nsheet square\nturn over left-right\n") `shouldBe` Just (FoundWord "turn")
      locationOf "\nfoldseq 1\nsheet square\n" `shouldBe` Just "t:1:1"
      locationOf "# a comment first\nfoldseq 1\nsheet square\n" `shouldBe` Just "t:1:1"

    it "says a statement stopped short at the end of its line" $
      fmap problemFound (problemOf (inStep "fold valley")) `shouldBe` Just FoundLineEnd

    -- A point or a line can start with fifteen different words. Listing them
    -- all is no help, and one of them used to be listed twice.
    it "says what could have come next in few words, each once" $ do
      fmap problemExpected (problemOf (inStep "fold valley a to")) `shouldBe` Just ["a point or a line"]
      fmap problemExpected (problemOf (inStep "not modelled \"left open")) `shouldBe` Just ["the closing quote of the string"]
      -- Another blank line could have come too, and it says so.
      fmap problemExpected (problemOf "foldseq 1\nsheet square\nstep { turn over left-right }\n}\n")
        `shouldBe` Just ["a new line or \";\"", "a step or the closing caption"]

    -- A @{@ first is looked for, to say the text looks like a FOLD file. That
    -- look must not turn into an offer.
    it "does not offer { as a way to start a source" $
      fmap problemExpected (problemOf "Foldseq 1\nsheet square\n") `shouldBe` Just ["\"foldseq\""]

-- | A source holding one step with these moves in it, the moves on line 4.
inStep :: Text -> Text
inStep moves = "foldseq 1\nsheet square\nstep {\n  " <> moves <> "\n}\n"

-- | The moves of that one step, positions stripped.
oneStep :: Text -> Either SequenceError [Move]
oneStep moves =
  concatMap (map locValue . stepMoves . locValue) . seqSteps . stripSpans <$> parseSequence "t" (inStep moves)

-- | The moves a builder's body makes.
movesOf :: Moves () -> [Move]
movesOf body = concatMap (map locValue . stepMoves . locValue) (seqSteps (sequenceOf (header "T" sheetSquare Nothing) (stepUncaptioned_ body)))

problemOf :: Text -> Maybe ParseProblem
problemOf = problemIn "t"

problemIn :: FilePath -> Text -> Maybe ParseProblem
problemIn path text = case parseSequence path text of
  Left (ParseFailed problem) -> Just problem
  _ -> Nothing

-- | The hint a source fails with, and where.
mistake :: Text -> Maybe (Hint, Text)
mistake = mistakeIn "t"

mistakeIn :: FilePath -> Text -> Maybe (Hint, Text)
mistakeIn path text = do
  problem <- problemIn path text
  hint <- problemHint problem
  place <- sourceLocation (ParseFailed problem)
  pure (hint, place)

locationOf :: Text -> Maybe Text
locationOf text = problemOf text >>= sourceLocation . ParseFailed

-- | Every word of a printed sequence that is outside a string literal.
wordsOutsideStrings :: Text -> [Text]
wordsOutsideStrings = go . T.unpack
  where
    go = \case
      [] -> []
      '"' : rest -> go (afterString rest)
      c : rest
        | isAlpha c -> let (word, more) = span wordChar (c : rest) in T.pack word : go more
        | otherwise -> go rest
    afterString = \case
      [] -> []
      '\\' : _ : rest -> afterString rest
      '"' : rest -> rest
      _ : rest -> afterString rest
    wordChar c = isAlphaNum c || c == '-' || c == '_'

-- | The words a sequence brings with it: its names, and the kinds of refusal
-- it expects, which are words starting with a capital and never reserved.
ownWords :: Sequence -> Set.Set Text
ownWords s = Set.fromList (filter mayBeOwn (wordsOutsideStrings (prettySequence s)))
  where
    mayBeOwn word = word `elem` namePool || word `elem` kindPool
