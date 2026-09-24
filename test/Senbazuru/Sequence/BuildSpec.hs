-- |
-- Tests for the Haskell way of writing a fold sequence.
--
-- A builder is a thin thing: it appends a constructor. So the test worth having
-- is not \"does 'fold' call 'Fold'\" but \"is the value that comes out the
-- value a person would expect from reading the @do@ block\", and the way to
-- say that is to write the expected tree out in constructors and compare.
-- 'everyBuilder' does that once for every function the module exports, which
-- pins the things a builder can quietly get wrong: a default that drifts from
-- the parser's, steps or moves coming out in the wrong order, a body's moves
-- leaking into the next step, a caption of @""@ where there should be none.
--
-- The import list is part of the test, as it is in the syntax tree's spec.
-- @Prelude@, "Senbazuru.Fold.Types", "Senbazuru.Sequence.Syntax" and
-- "Senbazuru.Sequence.Build" are all imported whole and unqualified, which is
-- how they meet at a GHCi prompt. A builder named @repeat@, @until@ or @all@,
-- or a clash with a file's @Mountain@, @Valley@ or @Above@, stops this module
-- compiling.
--
-- What no test here can show is what the /types/ refuse: a move outside a
-- step, a step inside a step, a point's 'Ref' where a step's belongs. Those
-- are compile errors, and a test suite holds only code that compiles.
module Senbazuru.Sequence.BuildSpec (spec) where

import Control.Monad (void)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Syntax
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck
import Test.SequenceExamples (blintz, blintzCaptions)
import Test.SequenceHelpers (built, plainHeader)

spec :: Spec
spec = do
  describe "the blintz" $ do
    it "is the tree its do block reads as, with the loop unrolled" $
      blintz
        `shouldBe` Sequence
          (titledHeader "Blintz base, then reopen one corner" (SheetFile "examples/blintz-base.fold") (Just Centre))
          ( [ foldCornerBehind (Just "c1") SouthEast "south-east",
              foldCornerBehind Nothing NorthEast "north-east",
              foldCornerBehind Nothing NorthWest "north-west",
              foldCornerBehind Nothing SouthWest "south-west"
            ]
              <> [built (Step Nothing (Just "Reopen the first corner.") [built (Unfold ["c1"])])]
          )

    it "has the five captions its text will have" $
      map (stepCaption . locValue) (seqSteps blintz) `shouldBe` map Just blintzCaptions

  describe "steps" $ do
    prop "come out in the order written, one per call, each with its own moves" $
      forAll (listOf (T.pack <$> arbitrary)) $ \captions ->
        let steps = map locValue (seqSteps (sequenceOf squareHeader (mapM_ (\c -> step_ c (turnOver LeftRight)) captions)))
         in (map stepCaption steps, map (map locValue . stepMoves) steps)
              === (map Just captions, map (const [TurnOver LeftRight]) captions)

    -- Text may leave a caption out, and the tree records that it did, so these
    -- two are different steps and print differently.
    it "keep no caption apart from an empty one" $
      map (stepCaption . locValue) (seqSteps (sequenceOf squareHeader (stepUncaptioned_ (pure ()) >> step_ "" (pure ()))))
        `shouldBe` [Nothing, Just ""]

    it "hand a point marked in one step to the steps after it" $ do
      let marked = sequenceOf squareHeader $ do
            (_, tip) <- stepReturning "open" "Mark the tip." $ mark "tip" (cornerOf NorthEast) Nothing
            step_ "Fold it down." $ fold valley (point tip `onto` centre)
      map (map locValue . stepMoves . locValue) (seqSteps marked)
        `shouldBe` [ [Mark "tip" (CornerOf NorthEast) Nothing],
                     [Fold ValleyFold ToFlat (Onto (PointNamed "tip") Centre) FlapOfFirstArgument Nothing]
                   ]

    -- 'together' hands back what its body returned, so a name defined inside
    -- the block can be used after it. Checking the 'Ref' alone would not be
    -- enough: a 'together' that ran its body twice, once for the moves and
    -- once for the result, would return the right name and mark the point
    -- twice. So the whole list is compared, and the mark appears in it once.
    it "hand a point marked inside together to the moves after it" $
      movesOfOnly (together (mark "tip" (cornerOf NorthEast) Nothing) >>= \tip -> anchor (point tip))
        `shouldBe` [ Together [built (Mark "tip" (CornerOf NorthEast) Nothing)],
                     Anchor (PointNamed "tip")
                   ]

  describe "header" $
    it "leaves every line it was not given as a source that omits it would" $
      header "A square" sheetSquare Nothing `shouldBe` titledHeader "A square" UnitSquare Nothing

  describe "every builder" $ do
    it "appends the constructor its text would parse to" $
      everyBuilder `shouldBe` everyBuilderExpected

    it "carries no span anywhere" $
      stripSpans everyBuilder `shouldBe` everyBuilder

    it "is already canonical" $
      canonical everyBuilder `shouldBe` everyBuilder

  describe "canonical values" $ do
    -- The parser cannot know that a bare name on the right of @let@ is a line,
    -- so it reads it as a point; a built value has to be that same tree to
    -- equal the parse of its own text.
    it "stores a let of a bare line name as the point the parser would read" $
      movesOfOnly (letLine "m" (LineNamed "l")) `shouldBe` [Let "m" (BindPoint (PointNamed "l"))]

    it "rewrites a value assembled from raw constructors too" $
      movesOfOnly (move (Fold valley ToFlat (PointToLine Centre (LineNamed "l")) FlapOfFirstArgument Nothing))
        `shouldBe` [Fold ValleyFold ToFlat (Onto Centre (PointNamed "l")) FlapOfFirstArgument Nothing]

  describe "the two vocabularies" $
    it "stay apart: a file's words and the builders of the same name" $ do
      ([Mountain, Valley] :: [Assignment]) `shouldBe` [Mountain, Valley]
      ([Above] :: [Stacking]) `shouldBe` [Above]
      ([mountain, valley, behind, inFront] :: [Sense]) `shouldBe` [MountainFold, ValleyFold, MountainFold, ValleyFold]
      (centre `above` cornerOf SouthWest) `shouldBe` LayerAbove Centre (CornerOf SouthWest)

-- | A sequence that calls every function "Senbazuru.Sequence.Build" exports,
-- except 'sheetFile', which the blintz uses. It folds nothing sensible: the
-- builder checks no geometry, and this checks only the builder.
--
-- \"Every\" is kept true by hand. Nothing fails when a builder is added to the
-- module and not to this list, so adding one means adding it here and to
-- 'everyBuilderExpected', in the same change.
everyBuilder :: Sequence
everyBuilder = sequenceOf (header "Every builder" sheetSquare (Just (at (3 / 4) (1 / 4)))) $ do
  (open, (tip, diagonal)) <- stepReturning "open" "Name a point and two lines." $ do
    tip <- mark "tip" (cornerOf NorthEast) (Just centre)
    diagonal <- letLine "diagonal" (cornerOf SouthWest `onto` cornerOf NorthEast)
    _ <- letLine "same" (namedLine diagonal)
    preCrease valley (namedLine diagonal)
    pure (tip, diagonal)
  base <- stepUncaptioned "base" $ do
    apex <- letPoint "apex" (point tip)
    collapse (point apex) (Just (centre, cornerOf SouthEast)) 180
  step_ "Carry it further, then shape two flaps at once." $ do
    continue base 90
    together $ do
      rabbitEar centre 90
      petal TopFlapTip 45
  stepUncaptioned_ $ do
    turnOver TopBottom
    rotate 2 Anticlockwise
    anchor (endOfCreaseOf open centre)
  _ <- step "rest" "Everything else." $ do
    fold inFront (hingeOf open)
    fold behind (creaseOf open)
    fold mountain (edge West)
    move (Fold valley (Degrees 90) (namedLine diagonal) allLayers (Just (point tip)))
    move (Fold valley ToFlat (edge North) (topLayers 2) Nothing)
    move (Fold valley ToFlat (edge South) topFlap Nothing)
    unfold [open, base]
    pose [(centre, cornerOf NorthWest, -90)]
    repeatSteps open (Just base) (Just (TurnedQuarters 2 centre))
    checkpoint "half.fold" (Relations [point tip `above` centre])
    notModelled "inside reverse fold"
    expectRefused (RefusalKind "ExistingHingeFlat") (Unfold [refName open])
  pure ()

-- | 'everyBuilder', written out. __The third move of the first step looks
-- wrong and is not:__ @letLine "same" (namedLine diagonal)@ stores a /point/
-- binding, because that is how the parser reads @let same = diagonal@.
everyBuilderExpected :: Sequence
everyBuilderExpected =
  Sequence
    (titledHeader "Every builder" UnitSquare (Just (AtSheet (3 / 4) (1 / 4))))
    [ built $
        Step
          (Just "open")
          (Just "Name a point and two lines.")
          [ built (Mark "tip" (CornerOf NorthEast) (Just Centre)),
            built (Let "diagonal" (BindLine (Onto (CornerOf SouthWest) (CornerOf NorthEast)))),
            built (Let "same" (BindPoint (PointNamed "diagonal"))),
            built (FoldAndUnfold ValleyFold (LineNamed "diagonal") FlapOfFirstArgument Nothing)
          ],
      built $
        Step
          (Just "base")
          Nothing
          [ built (Let "apex" (BindPoint (PointNamed "tip"))),
            built (Macro (Collapse (PointNamed "apex") (Just (Centre, CornerOf SouthEast)) 180) [])
          ],
      built $
        Step
          Nothing
          (Just "Carry it further, then shape two flaps at once.")
          [ built (Continue "base" 90),
            built (Together [built (Macro (RabbitEar Centre 90) []), built (Macro (Petal TopFlapTip 45) [])])
          ],
      built $
        Step
          Nothing
          Nothing
          [ built (TurnOver TopBottom),
            built (Rotate 2 Anticlockwise),
            built (Anchor (EndOfCreaseOf "open" Centre))
          ],
      built $
        Step
          (Just "rest")
          (Just "Everything else.")
          [ built (Fold ValleyFold ToFlat (HingeOf "open") FlapOfFirstArgument Nothing),
            built (Fold MountainFold ToFlat (CreaseOf "open") FlapOfFirstArgument Nothing),
            built (Fold MountainFold ToFlat (EdgeOf West) FlapOfFirstArgument Nothing),
            built (Fold ValleyFold (Degrees 90) (LineNamed "diagonal") AllLayers (Just (PointNamed "tip"))),
            built (Fold ValleyFold ToFlat (EdgeOf North) (TopLayers 2) Nothing),
            built (Fold ValleyFold ToFlat (EdgeOf South) TopFlap Nothing),
            built (Unfold ["open", "base"]),
            built (Pose [(Centre, CornerOf NorthWest, -90)]),
            built (Repeat "open" (Just "base") (Just (TurnedQuarters 2 Centre))),
            built (Checkpoint "half.fold" (Relations [LayerAbove (PointNamed "tip") Centre])),
            built (NotModelled "inside reverse fold"),
            built (ExpectRefused (RefusalKind "ExistingHingeFlat") (Unfold ["open"]))
          ]
    ]

-- | The header 'header' ought to make: the shared defaults, a title, and
-- perhaps an anchor. Written with the constructors and not with 'header',
-- which is what it is compared with.
titledHeader :: Text -> SheetSource -> Maybe Point -> Header
titledHeader title sheet anchorPoint =
  (plainHeader sheet) {hTitle = Just title, hAnchor = built <$> anchorPoint}

squareHeader :: Header
squareHeader = header "A square" sheetSquare Nothing

-- | One of the blintz's first four steps.
foldCornerBehind :: Maybe Name -> Corner -> Text -> Located Step
foldCornerBehind name corner word =
  built $
    Step
      name
      (Just ("Fold the " <> word <> " corner behind, to the centre."))
      [built (Fold MountainFold ToFlat (Onto (CornerOf corner) Centre) FlapOfFirstArgument Nothing)]

-- | The moves of a sequence whose one step has this body.
movesOfOnly :: Moves a -> [Move]
movesOfOnly body =
  [ locValue m
    | s <- seqSteps (sequenceOf squareHeader (stepUncaptioned_ (void body))),
      m <- stepMoves (locValue s)
  ]
