-- |
-- Tests for the fold-sequence tree and the three functions that live beside it.
--
-- The tree itself is data and has nothing to test. What is worth pinning is
-- what the rest of the language will lean on without looking:
--
-- * 'canonical' is what makes \"print, then parse, and you get the sequence
--   back\" a true sentence, so its four rewrites are pinned one by one, and
--   then as properties over random trees, where the rewrites have to be found
--   inside points, inside moves and inside the header.
-- * 'stripSpans' is what lets a parsed sequence equal a built one. The way it
--   goes wrong is by /missing/ a span when the tree grows a new place to keep
--   one. A checker written as a second walk over the tree would miss the same
--   place, so the property here reads the derived 'Show' output instead, which
--   cannot forget a field.
-- * 'sourceFiles' decides which file on disk a sequence means, and the wrong
--   rule — resolving against the directory the command ran in — works in every
--   test run from the repository root and nowhere else.
--
-- The import list is part of the test. "Senbazuru.Fold.Types" and
-- "Senbazuru.Sequence.Syntax" are both imported whole and unqualified, as the
-- module that runs a sequence will have to import them, and 'fileWords' and
-- 'sequenceWords' use the constructors the two vocabularies nearly share. If a
-- syntax constructor is ever renamed to @Mountain@, @Valley@ or @Above@, this
-- module stops compiling with an ambiguity error, which is the failure the
-- longer names were chosen to avoid.
module Senbazuru.Sequence.SyntaxSpec (spec) where

import Data.Char (isDigit)
import Data.List (isPrefixOf)
import Senbazuru.Fold.Types
import Senbazuru.Sequence.Syntax
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.SequenceGen (genSequence, genSequenceWith)
import Test.SequenceHelpers (plainHeader)

-- | A file's words for a crease and for two stacked faces.
fileWords :: ([Assignment], [Stacking])
fileWords = ([Mountain, Valley], [Above])

-- | The sequence language's words for the nearest ideas.
sequenceWords :: ([Sense], Relation)
sequenceWords = ([MountainFold, ValleyFold], LayerAbove Centre Centre)

spec :: Spec
spec = do
  describe "the two vocabularies" $
    it "can be imported side by side without qualification" $ do
      fileWords `shouldBe` ([Mountain, Valley], [Above])
      sequenceWords `shouldBe` ([MountainFold, ValleyFold], LayerAbove Centre Centre)

  describe "canonical" $ do
    it "reads a point laid onto a bare name as point onto point" $
      canonicalFold (PointToLine (CornerOf SouthWest) (LineNamed "b"))
        `shouldBe` [Onto (CornerOf SouthWest) (PointNamed "b")]

    it "reads a bare name laid onto a bare name as point onto point" $
      canonicalFold (LineOnto (LineNamed "a") (LineNamed "b") Nothing)
        `shouldBe` [Onto (PointNamed "a") (PointNamed "b")]

    it "reads a bare name laid onto any other line as point onto line" $
      canonicalFold (LineOnto (LineNamed "a") (EdgeOf North) Nothing)
        `shouldBe` [PointToLine (PointNamed "a") (EdgeOf North)]

    it "reads a let of a bare name as a point" $
      canonicalMoves [Let "n" (BindLine (LineNamed "b"))]
        `shouldBe` [Let "n" (BindPoint (PointNamed "b"))]

    -- The rule is about a bare /name/, not about @let@: a line that says what
    -- it is stays a line, and a line inside it is still rewritten.
    it "keeps a let of any other line as a line" $
      canonicalMoves
        [ Let "n" (BindLine (EdgeOf North)),
          Let "m" (BindLine (PointToLine Centre (LineNamed "b")))
        ]
        `shouldBe` [ Let "n" (BindLine (EdgeOf North)),
                     Let "m" (BindLine (Onto Centre (PointNamed "b")))
                   ]

    -- @nearest@ can only end the line-to-line form, so the text has already
    -- said that both names are lines and there is nothing to guess.
    it "leaves a line laid onto a line alone once nearest has been written" $ do
      let line = LineOnto (LineNamed "a") (LineNamed "b") (Just Centre)
      canonicalFold line `shouldBe` [line]

    it "leaves a line that is not a bare name where it is" $ do
      let line = LineOnto (EdgeOf West) (LineNamed "b") Nothing
      canonicalFold line `shouldBe` [line]

    -- The shapes are looked for everywhere a line can be written, not only at
    -- the line a fold names: inside another line, inside a point, inside a
    -- nested move, and in the header.
    it "rewrites a line nested inside another line" $
      canonicalFold (PerpendicularThrough (PointToLine Centre (LineNamed "b")) Centre)
        `shouldBe` [PerpendicularThrough (Onto Centre (PointNamed "b")) Centre]

    it "rewrites a line inside a point" $
      canonicalMoves [Anchor (Meet (PointToLine Centre (LineNamed "b")) (EdgeOf East))]
        `shouldBe` [Anchor (Meet (Onto Centre (PointNamed "b")) (EdgeOf East))]

    it "rewrites inside together and expect refused" $ do
      let inner = Fold ValleyFold ToFlat (PointToLine Centre (LineNamed "b")) FlapOfFirstArgument Nothing
          fixed = Fold ValleyFold ToFlat (Onto Centre (PointNamed "b")) FlapOfFirstArgument Nothing
      canonicalMoves [Together [Located NoSpan inner], ExpectRefused (RefusalKind "K") inner]
        `shouldBe` [Together [Located NoSpan fixed], ExpectRefused (RefusalKind "K") fixed]

    it "rewrites the header's anchor and its starting relations" $ do
      let meeting line = Meet line (EdgeOf East)
          asBuilt = PointToLine Centre (LineNamed "b")
          asParsed = Onto Centre (PointNamed "b")
          headerWith line =
            (plainHeader UnitSquare)
              { hAnchor = Just (Located NoSpan (meeting line)),
                hStart = Located NoSpan (StartFolded (Relations [LayerAbove (meeting line) Centre]))
              }
      canonical (Sequence (headerWith asBuilt) []) `shouldBe` Sequence (headerWith asParsed) []

    -- 'checkCoverage' fails the property if too few of the generated trees
    -- held anything to rewrite, which is what would make the other two
    -- properties pass without having tested anything.
    prop "is idempotent, on trees that often need rewriting" $
      checkCoverage $
        forAll genSequence $ \s ->
          cover 25 (canonical s /= s) "held a shape to rewrite" $
            canonical (canonical s) === canonical s

    prop "does not care whether spans are stripped first" $
      forAll genSequence $ \s ->
        canonical (stripSpans s) === stripSpans (canonical s)

  describe "stripSpans" $ do
    prop "removes every span, and changes nothing else" $
      forAll genSequence $ \s ->
        show (stripSpans s) === eraseSpans (show s)

    prop "leaves a sequence built without spans as it was" $
      forAll (genSequenceWith (pure NoSpan)) $ \s ->
        stripSpans s === s

  describe "sourceFiles" $ do
    it "finds a relative sheet beside the source, and keys it as written" $
      sourceFiles "examples/w.foldseq" (Sequence (plainHeader (SheetFile "crane.fold")) [])
        `shouldBe` [SourceFile "crane.fold" "examples/crane.fold" NoSpan]

    it "does not invent a directory for a source that has none" $
      sourceFiles "w.foldseq" (Sequence (plainHeader (SheetFile "crane.fold")) [])
        `shouldBe` [SourceFile "crane.fold" "crane.fold" NoSpan]

    it "keeps an absolute path" $
      sourceFiles "examples/w.foldseq" (Sequence (plainHeader (SheetFile "/abs/base.fold")) [])
        `shouldBe` [SourceFile "/abs/base.fold" "/abs/base.fold" NoSpan]

    it "names no file for a plain square" $
      sourceFiles "examples/w.foldseq" (Sequence (plainHeader UnitSquare) []) `shouldBe` []

    -- The checkpoint inside @expect refused@ has no span of its own, so it
    -- takes the span of the move written around it; the one inside @together@
    -- has its own. The same file twice is two entries: each is a place a
    -- message may need to point at.
    it "lists the sheet, then every checkpoint in the order written" $ do
      let at line = Span "examples/w.foldseq" line 3 line 40
          checkpoint path = Checkpoint path StackingFirst
          steps =
            [ Located (at 5) $
                Step
                  Nothing
                  Nothing
                  [ Located (at 6) (TurnOver LeftRight),
                    Located (at 7) (checkpoint "half.fold"),
                    Located (at 8) (Together [Located (at 9) (checkpoint "/abs/base.fold")])
                  ],
              Located (at 12) $
                Step Nothing Nothing [Located (at 13) (ExpectRefused (RefusalKind "K") (checkpoint "half.fold"))]
            ]
          header = (plainHeader (SheetFile "crane.fold")) {hSheet = Located (at 3) (SheetFile "crane.fold")}
      sourceFiles "examples/w.foldseq" (Sequence header steps)
        `shouldBe` [ SourceFile "crane.fold" "examples/crane.fold" (at 3),
                     SourceFile "half.fold" "examples/half.fold" (at 7),
                     SourceFile "/abs/base.fold" "/abs/base.fold" (at 9),
                     SourceFile "half.fold" "examples/half.fold" (at 13)
                   ]

-- | 'canonical', seen through a one-step sequence holding the given moves.
canonicalMoves :: [Move] -> [Move]
canonicalMoves moves =
  [ locValue move
    | step <- seqSteps (canonical (Sequence (plainHeader UnitSquare) [Located NoSpan (Step Nothing Nothing (map (Located NoSpan) moves))])),
      move <- stepMoves (locValue step)
  ]

-- | 'canonical', seen through the line of a single fold.
--
-- A list, and every expectation above asks for exactly one line. A 'canonical'
-- that lost the fold, made two of it or turned it into another move then gives
-- an answer no expectation accepts, including the two that expect the line
-- back unchanged.
canonicalFold :: Line -> [Line]
canonicalFold line =
  [ rewritten
    | Fold _ _ rewritten _ _ <- canonicalMoves [Fold ValleyFold ToFlat line FlapOfFirstArgument Nothing]
  ]

-- | Replace every shown 'Span' in a 'show'n value with @NoSpan@.
--
-- A span shows as @Span "path" 1 2 3 4@. The generator's paths hold no quote
-- and its positions are never negative, so the text to drop is: the opening,
-- everything up to the closing quote, and then four numbers each after one
-- space. @NoSpan@ is not touched, because the match needs the space and the
-- quote that follow a real constructor.
eraseSpans :: String -> String
eraseSpans text
  | opening `isPrefixOf` text = "NoSpan" <> eraseSpans (dropNumbers 4 afterPath)
  | otherwise = case text of
      [] -> []
      c : rest -> c : eraseSpans rest
  where
    opening = "Span \""
    afterPath = drop 1 (dropWhile (/= '"') (drop (length opening) text))

    dropNumbers :: Int -> String -> String
    dropNumbers 0 rest = rest
    dropNumbers n rest = dropNumbers (n - 1) (dropWhile isDigit (drop 1 rest))
