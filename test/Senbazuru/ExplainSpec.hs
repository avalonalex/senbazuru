-- |
-- Tests for the one class every error type in the library answers.
--
-- Two things are worth pinning. One is the /convention/ the class exists to
-- carry: a message is a fragment a caller can drop after a colon, so it starts
-- lower case and does not end in a full stop. Nothing in the type says that,
-- and it is the sort of rule a new instance breaks without anybody noticing
-- until a message reads @cannot render foo.fold: The frame ...@.
--
-- The other is the two instances nothing prints yet, 'FlatError' and
-- 'StepError'. They have no golden file and no CLI path to notice them, so
-- this is the only place their words are read.
module Senbazuru.ExplainSpec (spec) where

import Data.Char (isUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (LoadError (..), SaveError (..))
import Senbazuru.Fold.Query (FoldError (..), renderFoldError)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), VertexId (..))
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
      [name | (name, msg) <- everyType, not (startsLower msg)] `shouldBe` []

    it "ends without a full stop, so it can be followed by one" $
      [name | (name, msg) <- everyType, "." `T.isSuffixOf` msg] `shouldBe` []

  describe "an error nested inside another" $
    it "is quoted by the same method, not re-worded" $ do
      let inner = NoVertices
      explain (Check.FrameGeometry inner) `shouldBe` explain inner
      explain (Fold.FrameGeometry inner) `shouldBe` explain inner
      explain (Stack.StackingRefused inner) `shouldBe` explain inner
      explain (FlatRefused inner) `shouldBe` explain inner

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

  describe "the name a caller that predates the class still uses" $
    it "is the instance, so the two cannot drift apart" $ do
      let err = VertexIndexOutOfRange (EdgeId 1) (VertexId 9) 4
      renderFoldError err `shouldBe` explain err

-- | A message may open with a digit or a quote; what it may not open with is a
-- capital, which is what would read as a new sentence mid-line.
startsLower :: Text -> Bool
startsLower t = case T.uncons t of
  Just (c, _) -> not (isUpper c)
  Nothing -> False
