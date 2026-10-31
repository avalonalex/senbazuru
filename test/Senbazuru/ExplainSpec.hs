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
-- And how an id or a vector is written: as numbers, never as the record
-- Haskell's derived 'show' writes, @FaceId {unFaceId = 0}@ ("Senbazuru.Explain"
-- says why). 'SurfaceError' and 'PaperMeshError' printed twelve ids and two
-- vectors that way until #582, which also made the ids show as their numbers,
-- so an id can no longer print as a record anywhere; a vector still can.
-- 'idMessages' samples every constructor of both types, with the study's
-- messages the same fix touched, and holds each to the numbers it was given.
module Senbazuru.ExplainSpec (spec) where

import ContactDiscovery (DiscoveryError (AmbiguousReferenceOrder))
import Data.Char (isAlphaNum, isUpper)
import Data.Text (Text)
import Data.Text qualified as T
import FoldBending (BendingError (InvalidRestAngle, MissingRestAngle, UnexpectedRestAngle, UnsupportedCrease))
import Senbazuru.Explain (Explain (..), decimal, num)
import Senbazuru.Fold.Load (LoadError (..), SaveError (..))
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Import.Segments (ImportError (..))
-- Qualified, not because the modules are large but because three of them spell
-- the same fault: 'NotFlat' is a constructor of both CheckError and
-- StackingError, and 'FrameGeometry' of both CheckError and FoldingError. That
-- is not an accident to be worked around -- it is the duplication this class
-- was introduced to make visible.

import Senbazuru.Origami.Flap (FlapError (..))
import Senbazuru.Origami.Flat (FlatError (..))
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
import Senbazuru.Sequence.Syntax (Name (..), Span (..))
import SurfaceContact (ContactError (UnknownContactPanel))
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
    ("SequenceError, a page", explain (PageRefused 2 (Just (3, Just (Name "crane"))) (GaveUpStacking 1))),
    ("WriteProblem", explain (WriteMissingAngles 12 11)),
    ("MoveFailure", explain (MoveNotRunYet "\"turn over\"")),
    ("SelectionError", explain (SeedMissing ["corner south-west", "centre"])),
    ("SelectionError", explain (SeedMissing [])),
    ("ParseProblem", explain (ParseProblem NoSpan FoundEnd ["a step"] Nothing)),
    ("StaticProblem", explain EmptyStep),
    ("RunOptionError", explain (NotWithCheck ["-o", "--report"])),
    ("RunOptionError, a frame", explain (NoSuchFrame 0 3)),
    ("RunOptionError, no states", explain NoStates)
  ]

-- | Every constructor of 'SurfaceError' and 'PaperMeshError', and the study's
-- messages the same fix touched, each with the numbers its message must show.
-- The ids are all different, so a message that printed one id twice, or none,
-- leaves a number out. 'surfaceName' and 'paperName' match without a
-- catch-all, so that a constructor added to either type without a sample here
-- at least warns there, as "Senbazuru.Sequence.ErrorSpec" does for its types.
idMessages :: [(String, Text, [Text])]
idMessages =
  [("SurfaceError " <> surfaceName e, explain e, shown) | (e, shown) <- surfaceSamples]
    <> [("PaperMeshError " <> paperName e, explain e, shown) | (e, shown) <- paperSamples]
    <> [ ("BendingError MissingRestAngle", explain (MissingRestAngle (EdgeId 23)), ["23"]),
         ("BendingError UnexpectedRestAngle", explain (UnexpectedRestAngle (EdgeId 24)), ["24"]),
         ("BendingError InvalidRestAngle", explain (InvalidRestAngle (EdgeId 25) 4), ["25", "4.0"]),
         ("BendingError UnsupportedCrease", explain (UnsupportedCrease (EdgeId 26)), ["26"]),
         ("ContactError UnknownContactPanel", explain (UnknownContactPanel (FaceId 27)), ["27"]),
         ("DiscoveryError AmbiguousReferenceOrder", explain (AmbiguousReferenceOrder (FaceId 28) (FaceId 29)), ["28", "29"])
       ]

surfaceSamples :: [(SurfaceError, [Text])]
surfaceSamples =
  [ (SurfaceFrameError NoVertices, []),
    (SurfaceNonFinite (VertexId 3), ["3"]),
    (SurfaceMaterialMismatch, []),
    (SurfaceMaterialNotFlat (VertexId 4), ["4"]),
    (SurfaceMissingMaterial (VertexId 5), ["5"]),
    (SurfaceInvalidMaterialCoordinates, []),
    (SurfaceMaterialCount 6 7, ["6", "7"]),
    (SurfaceInvalidMaterialPoint (VertexId 8), ["8"]),
    (SurfaceBadThickness (-1), ["-1.0"]),
    (SurfaceBadDirection (V3 0 0 (0 / 0)), ["(0.0, 0.0, NaN)"]),
    (SurfaceBadLayerPair (FaceId 9) (FaceId 10), ["9", "10"]),
    (SurfaceBadRefinement 11, ["11"]),
    (SurfaceUnknownRefinementPanel (FaceId 12), ["12"]),
    (SurfaceNonConvex (FaceId 13), ["13"]),
    (SurfaceNonPlanar (FaceId 14), ["14"]),
    (SurfaceDegenerateFan (FaceId 15), ["15"]),
    (SurfaceJoinedCut (EdgeId 16), ["16"]),
    (SurfaceMissingVertex (VertexId 17), ["17"])
  ]

paperSamples :: [(PaperMeshError, [Text])]
paperSamples =
  [ (PaperSurfaceError (SurfaceNonConvex (FaceId 18)), ["18"]),
    (PaperOrderError NoVertices, []),
    (PaperNotPlanar (FaceId 19), ["19"]),
    (PaperUnresolved [FaceId 20, FaceId 21], ["20", "21"]),
    (PaperMissingPoint (FaceId 22) (V2 0.25 0.5), ["22", "(0.250000, 0.500000)"]),
    (PaperBadPrecision (-1), ["-1.0"])
  ]

surfaceName :: SurfaceError -> String
surfaceName = \case
  SurfaceFrameError {} -> "SurfaceFrameError"
  SurfaceNonFinite {} -> "SurfaceNonFinite"
  SurfaceMaterialMismatch -> "SurfaceMaterialMismatch"
  SurfaceMaterialNotFlat {} -> "SurfaceMaterialNotFlat"
  SurfaceMissingMaterial {} -> "SurfaceMissingMaterial"
  SurfaceInvalidMaterialCoordinates -> "SurfaceInvalidMaterialCoordinates"
  SurfaceMaterialCount {} -> "SurfaceMaterialCount"
  SurfaceInvalidMaterialPoint {} -> "SurfaceInvalidMaterialPoint"
  SurfaceBadThickness {} -> "SurfaceBadThickness"
  SurfaceBadDirection {} -> "SurfaceBadDirection"
  SurfaceBadLayerPair {} -> "SurfaceBadLayerPair"
  SurfaceBadRefinement {} -> "SurfaceBadRefinement"
  SurfaceUnknownRefinementPanel {} -> "SurfaceUnknownRefinementPanel"
  SurfaceNonConvex {} -> "SurfaceNonConvex"
  SurfaceNonPlanar {} -> "SurfaceNonPlanar"
  SurfaceDegenerateFan {} -> "SurfaceDegenerateFan"
  SurfaceJoinedCut {} -> "SurfaceJoinedCut"
  SurfaceMissingVertex {} -> "SurfaceMissingVertex"

paperName :: PaperMeshError -> String
paperName = \case
  PaperSurfaceError {} -> "PaperSurfaceError"
  PaperOrderError {} -> "PaperOrderError"
  PaperNotPlanar {} -> "PaperNotPlanar"
  PaperUnresolved {} -> "PaperUnresolved"
  PaperMissingPoint {} -> "PaperMissingPoint"
  PaperBadPrecision {} -> "PaperBadPrecision"

-- | Every message the shape rules hold: one of each library type, and every
-- one that names an id.
allMessages :: [(String, Text)]
allMessages = everyType <> [(name, msg) | (name, msg, _) <- idMessages]

-- | Whether a message holds a record as Haskell's derived 'show' writes one:
-- an opening brace, a field name and an equals sign. A brace alone is not
-- enough, since a sequence's own text, quoted in a message, has braces.
showsARecord :: Text -> Bool
showsARecord msg = any field (drop 1 (T.splitOn "{" msg))
  where
    field rest = case T.breakOn " = " rest of
      (name, value) -> not (T.null value) && not (T.null name) && T.all (\c -> isAlphaNum c || c `elem` ("_'" :: String)) name

spec :: Spec
spec = do
  describe "the shape every message keeps" $ do
    it "says something" $
      [name | (name, msg) <- allMessages, T.null msg] `shouldBe` []

    it "does not open with a capital, so it can follow a colon" $
      [name | (name, msg) <- allMessages, opensWithCapital msg] `shouldBe` []

    it "ends without a full stop, so it can be followed by one" $
      [name | (name, msg) <- allMessages, "." `T.isSuffixOf` msg] `shouldBe` []

  -- The first turns red if the ids went back to showing as records; the
  -- second if a message printed a vector, or any other record, with 'tshow'
  -- of the value itself; the third if one printed the wrong id, the same id
  -- twice, or none. The pins say what is printed instead, the last on the
  -- path #579's fold takes to a sequence's author.
  describe "an id or a vector in a message" $ do
    it "shows an id as its number, inside any value" $ do
      show (VertexId 3, EdgeId 4, FaceId 5) `shouldBe` "(3,4,5)"
      show [FaceId 1, FaceId 2] `shouldBe` "[1,2]"
      show (SurfaceNonConvex (FaceId 13)) `shouldBe` "SurfaceNonConvex 13"

    it "is written as numbers, not as a Haskell record" $
      [name | (name, msg) <- allMessages, showsARecord msg] `shouldBe` []

    it "shows each number it was given" $
      [name | (name, msg, shown) <- idMessages, not (all (`T.isInfixOf` msg) shown)] `shouldBe` []

    it "names a face by its number, and a vector by its parts, through a run too" $ do
      explain (SurfaceNonConvex (FaceId 13)) `shouldBe` "surface panel 13 must be convex to triangulate by a fan"
      explain (SurfaceBadDirection (V3 0 0 (0 / 0))) `shouldBe` "layer requirements need a finite nonzero direction, got (0.0, 0.0, NaN)"
      explain (StepRefused 1 Nothing NoSpan (FlapRefused (FlapSurface (SurfaceNonConvex (FaceId 0)))))
        `shouldBe` "step 1: surface panel 0 must be convex to triangulate by a fan"

    -- D24: a refused page names the step that ended at the state, as a move
    -- refused there would, and never a figure, whose number a step with no
    -- state shifts. State 0 was made by no step, and is named as the writer
    -- names a state.
    it "names a page's refusal by its step, or state 0 by its number" $ do
      explain (PageRefused 2 (Just (3, Just (Name "crane"))) (FaceOrderSelf (FaceId 4)))
        `shouldBe` "step 3 (crane): the page cannot draw the state it ends at: " <> explain (FaceOrderSelf (FaceId 4))
      explain (PageRefused 2 (Just (3, Nothing)) (FaceOrderSelf (FaceId 4)))
        `shouldBe` "step 3: the page cannot draw the state it ends at: " <> explain (FaceOrderSelf (FaceId 4))
      explain (PageRefused 0 Nothing (FaceOrderSelf (FaceId 4)))
        `shouldBe` "state 0: the page cannot draw it: " <> explain (FaceOrderSelf (FaceId 4))

    -- A quarter turn of (1, 0) is (-0.0, 1), and a reader should not be
    -- shown a sign on nothing. A coordinate to type back in has no exponent:
    -- the sequence language cannot read one. Turns red if a zero kept its
    -- sign, or a coordinate under 0.1 were written as num writes it.
    it "writes a zero without a sign, and a coordinate without an exponent" $ do
      (num (-0.0), decimal (-0.0)) `shouldBe` ("0.000000", "0")
      map decimal [0.0625, 1 / 12, 5 / 6, 1] `shouldBe` ["0.0625", "0.083333", "0.833333", "1"]

    -- Each case turns red if the detector dropped one of its tests: the brace,
    -- the equals sign, or the field name before it, which tells a record
    -- from a sequence's own @{ mark p = centre }@.
    it "recognises a record, and not a sequence's braces" $ do
      map showsARecord ["surface panel FaceId {unFaceId = 10} must be convex", "got V3 {v3x = 0.0, v3y = 0.0, v3z = NaN}", "panels [FaceId {unFaceId = 1}]"]
        `shouldBe` [True, True, True]
      map showsARecord ["expect refused FlapCovered { fold … }", "step one { mark p = centre }", "the original z = 0 sheet"]
        `shouldBe` [False, False, False]

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
