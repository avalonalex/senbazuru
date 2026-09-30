-- | The paper screen of a pose read from the surface its gallery writes:
-- which edges it takes for joins, and what it leaves unmeasured.
module SurfaceScreenSpec (spec) where

import Data.Set qualified as S
import FoldBending (Hinge (..), HingeRole (..), hingeBends)
import PaperScreen (Turning (..), sheetChords)
import ScreenReport
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import SurfaceScreen
import Test.Hspec
import UncreasedSurface (uncreasedSurface)
import WingBending (BendingPiece (..), wingPiece)
import WingLayers

spec :: Spec
spec = describe "a pose screened from the surface its gallery writes" $ do
  it "takes for joins the edges its surface writes J: every panel bend, never the crease" $ do
    let edge h = let (a, b, _, _) = hingeVertices h in (min a b, max a b)
        bendsOf hinges = S.fromList [edge h | h <- hinges, hingeRole h == PanelBend]
    piece <- right (wingPiece 8 20)
    uncreased <- right (uncreasedSurface (pieceMesh piece))
    surfaceJoins uncreased `shouldBe` bendsOf (pieceHinges piece)
    S.size (surfaceJoins uncreased) `shouldBe` length (pieceHinges piece)
    layers <- right (wingLayers 8 0)
    folded <- right (layersSurface layers (layersMesh layers))
    surfaceJoins folded `shouldBe` bendsOf (layersHinges layers)
    S.size (surfaceJoins folded) `shouldSatisfy` (< length (layersHinges layers))

  -- The diamond folded flat along its middle crease, as the flat control
  -- starts: two layers lying on each other.
  it "screens the folded diamond, counting its joins but not its crease" $ do
    fixture <- right (wingLayers 8 0)
    let mesh = layersMesh fixture
    sheet <- right (layersSurface fixture mesh)
    contact <- right (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (layersOwners fixture) mesh)
    chords <- right (sheetChords mesh)
    bends <- right (hingeBends (layersHinges fixture) mesh)
    screen <- right (surfaceScreen sheet chords contact bends mesh)
    -- The crease is folded flat, far past 45 degrees, and it is no join; no
    -- join is bent past 45 degrees. Nor does the pose fail on strain or the
    -- floor, so its verdict is that of a finer level not measured.
    length [() | (h, angle) <- bends, abs angle > pi / 4, SurfaceCrease _ <- [hingeRole h]] `shouldSatisfy` (> 0)
    screenTurning screen `shouldBe` Turning 0 0
    verdictOverall (screenVerdict screen) `shouldBe` NotMeasured
    -- Turn every hinge a quarter turn, as no mesh here does: every join the
    -- surface writes is counted, and nothing else.
    turned <- right (surfaceScreen sheet chords contact [(h, pi / 2) | (h, _) <- bends] mesh)
    turningJoins (screenTurning turned) `shouldBe` S.size (surfaceJoins sheet)
    S.size (surfaceJoins sheet) `shouldSatisfy` (\joins -> joins > 0 && joins < length bends)
    -- The screen counts the pairs its check flags; flag one by hand, not a
    -- real crossing.
    flagged <- right (surfaceScreen sheet chords contact {crossingPanels = [("triangle-0", "triangle-1")]} bends mesh)
    (screenCrossings screen, screenCrossings flagged) `shouldBe` (0, 1)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
