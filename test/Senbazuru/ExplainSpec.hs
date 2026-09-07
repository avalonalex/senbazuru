-- |
-- Tests for the one class every error type in the library answers.
--
-- Three things are worth pinning.
--
-- The /convention/ the class exists to carry: a message is a fragment a caller
-- can drop after a colon, so it starts lower case and does not end in a full
-- stop. Nothing in the type says that, and it is the sort of rule a new
-- instance breaks without anybody noticing until a message reads
-- @cannot render foo.fold: The frame ...@. 'everyType' samples one constructor
-- per type, which is eleven of the seventy-nine there are — enough to catch a
-- whole instance written the wrong way, not enough to catch one new arm added
-- to an existing one, and hand-maintained either way. Treat it as a worked
-- statement of the rule rather than as a guard.
--
-- The two instances nothing prints yet, 'FlatError' and
-- 'Senbazuru.Render.Steps.StepError'. They have no golden file and no CLI path
-- to notice them, so this is the only place their words are read.
--
-- And the arms that reach a /second/ instance, or deliberately do not forward
-- at all. Those used to be pinned by naming the inner module's rendering
-- function; under one method they are pinned by inference, and nothing but a
-- test now says which instance a nested error reaches.
module Senbazuru.ExplainSpec (spec) where

import Data.Char (isUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (LoadError (..), SaveError (..))
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (FaceId (..), VertexId (..))
import Senbazuru.Import.Segments (ImportError (..))
import Senbazuru.Origami.Flat (FlatError (..))
-- Qualified, not because the modules are large but because three of them spell
-- the same fault: 'NotFlat' is a constructor of both CheckError and
-- StackingError, and 'FrameGeometry' of both CheckError and FoldingError. That
-- is not an accident to be worked around -- it is the duplication this class
-- was introduced to make visible.
import Senbazuru.Origami.FlatFold qualified as Check
import Senbazuru.Origami.Folding qualified as Fold
import Senbazuru.Origami.Stacking qualified as Stack
import Senbazuru.Origami.ThroughLayers (ThroughError (..))
import Senbazuru.Render.Gltf (GltfError (..))
import Senbazuru.Render.Steps (StepError (..))
import Test.Hspec

-- | One error of each type in the library, already turned into words.
--
-- Named so that a failure says which type broke the rule. Deliberately a list
-- of 'Text' and not of errors: the types differ, so the only thing they have
-- in common is what the class produces.
everyType :: [(String, Text)]
everyType =
  [ ("FoldError", explain (VertexCoordTooShort (VertexId 3) 1)),
    ("LoadError", explain (ReadFailed "a.fold" "no such file")),
    ("SaveError", explain (WriteFailed "a.fold" "read-only")),
    ("ImportError", explain (UnknownLineType 7 12)),
    ("CheckError", explain (Check.NotFlat 0.25)),
    ("FoldingError", explain (Fold.DegenerateFace (FaceId 2))),
    ("FlatError", explain (PaperInTheAir 0.25)),
    ("StackingError", explain (Stack.NonConvexFace (FaceId 2))),
    ("ThroughError", explain LineWithoutLength),
    ("GltfError", explain (GltfConcaveFace (FaceId 2))),
    ("StepError", explain (StepError 2 NoVertices))
  ]

spec :: Spec
spec = do
  describe "the shape every message keeps" $ do
    it "says something" $
      [name | (name, msg) <- everyType, T.null msg] `shouldBe` []

    it "does not open with a capital, so it can follow a colon" $
      [name | (name, msg) <- everyType, opensWithCapital msg] `shouldBe` []

    it "ends without a full stop, so it can be followed by one" $
      [name | (name, msg) <- everyType, "." `T.isSuffixOf` msg] `shouldBe` []

  describe "an error nested inside another" $ do
    it "is quoted through the same method, whatever the inner type" $ do
      let inner = NoVertices
      explain (Check.FrameGeometry inner) `shouldBe` explain inner
      explain (Fold.FrameGeometry inner) `shouldBe` explain inner
      explain (Stack.StackingRefused inner) `shouldBe` explain inner
      explain (GltfRefused inner) `shouldBe` explain inner
      explain (FlatRefused inner) `shouldBe` explain inner

    -- The one arm in the library whose inner error is not a 'FoldError'. It
    -- used to name 'renderFoldingError', so the field's type was pinned by the
    -- call; now it is inference, and this is what pins it instead.
    it "reaches the FoldingError instance where ThroughError wraps one" $ do
      let inner = Fold.DegenerateFace (FaceId 7)
      explain (CannotFold inner) `shouldBe` explain inner

    -- Three arms are deliberately not pass-through. Asserting the general rule
    -- and stopping there would leave a reader free to "simplify" these away.
    it "is prefixed where the outer error has something to add" $ do
      explain (CannotCrease NoVertices)
        `shouldSatisfy` T.isSuffixOf (explain NoVertices)
      explain (ImportFailed "a.cp" EmptyPattern)
        `shouldSatisfy` T.isSuffixOf (explain EmptyPattern)

    -- And one is replaced outright: the frame's message is about painting,
    -- and here the reader has a way out that only the glTF backend knows.
    it "is replaced where the outer error knows a way out the inner does not" $
      explain (GltfRefused (ImpossibleStacking (FaceId 3)))
        `shouldSatisfy` T.isInfixOf "thickness of"

  -- Nothing prints these two today: every caller of 'flatSheet' flattens a
  -- 'FlatError' into its own error first, and the CLI takes a 'StepError'
  -- apart to put the file name between the frame number and the reason.
  describe "the instances nothing prints yet" $ do
    it "states the fact a FlatError carries, with nothing about what it stops" $
      explain (PaperInTheAir 0.25)
        `shouldBe` "the model spans 0.250000 in z, so it is not folded flat"

    it "leads a StepError with the frame, which is what the reader lacks" $
      explain (StepError 2 (VertexCoordTooShort (VertexId 0) 1))
        `shouldBe` "frame 2: vertex 0 has 1 coordinate(s); at least 2 (x, y) are required"

  -- 'num' is the one helper whose choice of formatter is load-bearing, and the
  -- reason lives below 0.1 where 'showGFloat' switches to an exponent. Every
  -- other assertion in the suite happens to sit above that, so swapping it for
  -- 'showFFloat (Just 6)' would leave the whole thing green while turning a
  -- refusal into "spans 0.000000 in z" -- the message that tells a reader their
  -- file is a folded form because a coordinate is off by nothing at all.
  describe "how a measured quantity is written" $ do
    it "keeps six digits rather than show's rounding" $
      explain (PaperInTheAir 0.30000000000000004)
        `shouldBe` "the model spans 0.300000 in z, so it is not folded flat"

    it "goes to an exponent below 0.1, so a tiny span is not printed as zero" $ do
      explain (PaperInTheAir 5.0e-2)
        `shouldBe` "the model spans 5.000000e-2 in z, so it is not folded flat"
      explain (PaperInTheAir 1.0e-6)
        `shouldBe` "the model spans 1.000000e-6 in z, so it is not folded flat"

-- | A message may open with a digit or a quote; what it may not open with is a
-- capital, which is what would read as a new sentence mid-line.
opensWithCapital :: Text -> Bool
opensWithCapital t = case T.uncons t of
  Just (c, _) -> isUpper c
  Nothing -> False
