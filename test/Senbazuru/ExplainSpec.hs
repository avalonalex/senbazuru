-- |
-- Tests for the one class every error type in the library answers.
--
-- Four things are worth pinning.
--
-- The /convention/ the class exists to carry: a message is a fragment a caller
-- can drop after a colon, so it starts lower case and does not end in a full
-- stop. Nothing in the type says that, and it is the sort of rule a new
-- instance breaks without anybody noticing until a message reads
-- @cannot render foo.fold: The frame ...@. 'everyType' samples each type,
-- fifteen of them, with one constructor each and a few with two or three:
-- enough to catch a whole instance written the wrong way, not enough to catch
-- one new arm added to an existing one, and hand-maintained either way. Treat it as a worked statement
-- of the rule rather than as a guard. The sequence language's three types are
-- the exception: "Senbazuru.Sequence.ErrorSpec" samples every constructor of
-- theirs.
--
-- The two instances nothing prints yet, 'FlatError' and
-- 'Senbazuru.Render.Steps.StepError'. They have no golden file and no CLI path
-- to notice them, so this is the only place their words are read.
--
-- The arms that reach a /second/ instance, or deliberately do not forward
-- at all. Those used to be pinned by naming the inner module's rendering
-- function; under one method they are pinned by inference, and nothing but a
-- test now says which instance a nested error reaches.
--
-- And how an id or a vector is written: as numbers, never as the Haskell
-- 'show' gives, @FaceId {unFaceId = 0}@. The ids are records, so 'tshow' of
-- an id itself prints the record, and a message has to take the number out
-- first ("Senbazuru.Explain"). 'SurfaceError' printed eleven ids and a vector
-- the Haskell way until #581, so 'carriesAnId' lists every constructor of it
-- and of 'PaperMeshError' that carries one.
module Senbazuru.ExplainSpec (spec) where

import Data.Char (isAlphaNum, isUpper)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (LoadError (..), SaveError (..))
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
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
import Senbazuru.Origami.Surface (SurfaceError (..))
import Senbazuru.Origami.ThroughLayers (ThroughError (..))
import Senbazuru.Render.Gltf (GltfError (..))
import Senbazuru.Render.PaperMesh (PaperMeshError (..))
import Senbazuru.Render.Steps (StepError (..))
import Senbazuru.Sequence.Error (CandidateLine (..), FoldedBy (..), Found (..), MoveFailure (..), ParseProblem (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), StaticProblem (..), TakenBecause (..), WriteProblem (..))
import Senbazuru.Sequence.RunPlan (RunOptionError (..))
import Senbazuru.Sequence.Syntax (Span (..))
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
    ("LoadError, a sequence source", explain (IsSequenceSource "Blintz.foldseq")),
    ("LoadError, not UTF-8", explain (NotUtf8 "Blintz.foldseq")),
    ("SaveError", explain (WriteFailed "a.fold" "read-only")),
    ("ImportError", explain (UnknownLineType 7 12)),
    ("CheckError", explain (Check.NotFlat 0.25)),
    ("FoldingError", explain (Fold.DegenerateFace (FaceId 2))),
    ("FlatError", explain (PaperInTheAir 0.25)),
    ("StackingError", explain (Stack.NonConvexFace (FaceId 2))),
    ("ThroughError", explain LineWithoutLength),
    ("GltfError", explain (GltfConcaveFace (FaceId 2))),
    ("StepError", explain (StepError 2 NoVertices)),
    ("SequenceError", explain (StaticRefused (InStep 2 Nothing) NoSpan EmptyStep)),
    ("SequenceError, a sheet", explain (SheetRefused NoSpan "a.fold" (SheetHasNoVertices 16))),
    ("SheetProblem", explain (SheetAlreadyFolded (ByRelief 0.25))),
    ("ResolveProblem", explain (NotInOneFace (V2 0.75 0.25) 0)),
    ("ResolveProblem, two answers", explain (NeedsNearest [CandidateLine (V2 0.5 0.5) (V2 1 1) True, CandidateLine (V2 0.5 0.5) (V2 1 (-1)) True])),
    ("ResolveProblem, a nearest that disagrees", explain (NearestDisagrees (V2 0 0) (CandidateLine (V2 0.5 0.5) (V2 0.7071067811865476 (-0.7071067811865476)) True) LaysStretchOntoStretch (CandidateLine (V2 0.5 0.5) (V2 0.7071067811865476 0.7071067811865476) True))),
    ("TakenBecause", explain OnlyOnPaper),
    ("CandidateLine", explain (CandidateLine (V2 1 0) (V2 0.7071067811865476 0.7071067811865476) False)),
    ("SequenceError, a reference", explain (ResolveRefused (InStep 2 Nothing) NoSpan "corner north-east" (OffThePaper (V2 2 2)))),
    ("SequenceError, a move", explain (StepRefused 5 Nothing NoSpan (UnfoldChangedSince (EdgeId 8)))),
    ("SequenceError, a state", explain (WriteRefused 2 (WriteNonFinite "senbazuru:material_coords[3]" (0 / 0)))),
    ("WriteProblem", explain (WriteMissingAngles 12 11)),
    ("MoveFailure", explain (MoveNotRunYet "\"turn over\"")),
    ("SelectionError", explain SeedMissing),
    ("ParseProblem", explain (ParseProblem NoSpan FoundEnd ["a step"] Nothing)),
    ("StaticProblem", explain EmptyStep),
    ("RunOptionError", explain (NotWithCheck ["-o", "--report"])),
    ("RunOptionError, a frame", explain (NoSuchFrame 0 3)),
    ("RunOptionError, no states", explain NoStates)
  ]

-- | Every message of 'SurfaceError' and 'PaperMeshError' that names a vertex,
-- an edge, a face or a vector, each id a different number so that a message
-- naming the wrong one would show it.
carriesAnId :: [(String, Text)]
carriesAnId =
  [ ("SurfaceNonFinite", explain (SurfaceNonFinite (VertexId 3))),
    ("SurfaceMaterialNotFlat", explain (SurfaceMaterialNotFlat (VertexId 4))),
    ("SurfaceMissingMaterial", explain (SurfaceMissingMaterial (VertexId 5))),
    ("SurfaceInvalidMaterialPoint", explain (SurfaceInvalidMaterialPoint (VertexId 6))),
    ("SurfaceBadDirection", explain (SurfaceBadDirection (V3 0 0 (0 / 0)))),
    ("SurfaceBadLayerPair", explain (SurfaceBadLayerPair (FaceId 7) (FaceId 8))),
    ("SurfaceUnknownRefinementPanel", explain (SurfaceUnknownRefinementPanel (FaceId 9))),
    ("SurfaceNonConvex", explain (SurfaceNonConvex (FaceId 10))),
    ("SurfaceNonPlanar", explain (SurfaceNonPlanar (FaceId 11))),
    ("SurfaceDegenerateFan", explain (SurfaceDegenerateFan (FaceId 12))),
    ("SurfaceJoinedCut", explain (SurfaceJoinedCut (EdgeId 13))),
    ("SurfaceMissingVertex", explain (SurfaceMissingVertex (VertexId 14))),
    ("PaperNotPlanar", explain (PaperNotPlanar (FaceId 15))),
    ("PaperUnresolved", explain (PaperUnresolved [FaceId 16, FaceId 17])),
    ("PaperMissingPoint", explain (PaperMissingPoint (FaceId 18) (V2 0.25 0.5)))
  ]

-- | Whether a message holds a record as Haskell's derived 'show' writes one:
-- an opening brace, a field name and an equals sign.
showsARecord :: Text -> Bool
showsARecord msg = any field (drop 1 (T.splitOn "{" msg))
  where
    field rest = case T.breakOn " = " rest of
      (name, value) -> not (T.null value) && not (T.null name) && T.all (\c -> isAlphaNum c || c `elem` ("_'" :: String)) name

spec :: Spec
spec = do
  describe "the shape every message keeps" $ do
    it "says something" $
      [name | (name, msg) <- everyType, T.null msg] `shouldBe` []

    it "does not open with a capital, so it can follow a colon" $
      [name | (name, msg) <- everyType, opensWithCapital msg] `shouldBe` []

    it "ends without a full stop, so it can be followed by one" $
      [name | (name, msg) <- everyType, "." `T.isSuffixOf` msg] `shouldBe` []

  -- Turns red if any of the fifteen went back to 'tshow' of the id itself.
  -- The two pinned word for word say what each prints instead.
  describe "an id or a vector in a message" $ do
    it "is written as numbers, not as a Haskell record" $
      [name | (name, msg) <- carriesAnId, showsARecord msg] `shouldBe` []

    it "names a face by its number, and a vector by its parts" $ do
      explain (SurfaceNonConvex (FaceId 10)) `shouldBe` "surface panel 10 must be convex to triangulate by a fan"
      explain (SurfaceBadDirection (V3 0 0 (0 / 0))) `shouldBe` "layer requirements need a finite nonzero direction, got (0.0, 0.0, NaN)"

    it "recognises the record it is looking for" $ do
      showsARecord "surface panel FaceId {unFaceId = 10} must be convex" `shouldBe` True
      showsARecord "got V3 {v3x = 0.0, v3y = 0.0, v3z = NaN}" `shouldBe` True
      showsARecord "expect refused FlapCovered { fold … }" `shouldBe` False

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
