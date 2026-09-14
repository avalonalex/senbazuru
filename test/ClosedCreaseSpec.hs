-- | A one-dimensional exact reference checks a two-dimensional material
-- mesh. The tiny-crossing control deliberately documents the numerical
-- checker's limit; passing that check is not proof of an ordered ideal sheet.
module ClosedCreaseSpec (spec) where

import ClosedCrease
import Control.Monad (forM_, when)
import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldBending
import FoldContact (contactGap)
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec

spec :: Spec
spec = describe "one nearly closed crease" $ do
  it "keeps one connected sheet, shared crease ids and unchanged material across controls" $
    forM_ [1, 2, 4] $ \n -> do
      reference <- right (closedCrease n FlatTouching)
      forM_ [minBound .. maxBound] $ \shape -> do
        fixture <- right (closedCrease n shape)
        let mesh = closedMesh fixture
            vertices ts = S.fromList [v | (a, b, c) <- ts, v <- [a, b, c]]
            (lower, upper) = splitAt (16 * n) (triangles mesh)
        triangles mesh `shouldBe` triangles (closedMesh reference)
        map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (closedMesh reference))
        S.intersection (vertices lower) (vertices upper) `shouldBe` S.fromList (closedRoot fixture)
        length (samples mesh) `shouldBe` 24 * n + 3
        componentCount mesh `shouldBe` 1
        maxLengthError mesh `shouldSatisfy` (< 1e-12)
        [position p | (i, p) <- zip [0 ..] (samples mesh), i `elem` closedRoot fixture] `shouldBe` [V3 0 (-0.5) 0, V3 0 0 0, V3 0 0.5 0]

  it "distinguishes touching, opening, crossing and reversed order with exact profile arithmetic" $
    forM_ [minBound .. maxBound] $ \shape -> do
      coarse <- right (closedCrease 1 shape)
      forM_ [1, 2, 4] $ \n -> do
        fixture <- right (closedCrease n shape)
        let gaps = map snd (profileGaps fixture)
        (minimum gaps, maximum gaps) `shouldBe` (minimum (map snd (profileGaps coarse)), maximum (map snd (profileGaps coarse)))
        profileCrossings fixture `shouldBe` profileCrossings coarse
        all (== 0) gaps `shouldBe` (shape `elem` [FlatTouching, BentTouching])
        any (< 0) gaps `shouldBe` (shape `elem` [Crossed, CrossedSliver, WrongSide])
        length (profileCrossings fixture) `shouldBe` (if shape `elem` [Crossed, CrossedSliver] then 1 else 0)

  it "measures the prescribed crease angle while panel bends remain separate" $
    forM_ [minBound .. maxBound] $ \shape -> do
      fixture <- right (closedCrease 2 shape)
      let hinges = [h | h <- closedHinges fixture, SurfaceCrease _ <- [hingeRole h]]
          points = IM.fromList (zip [0 ..] (samples (closedMesh fixture)))
          t = case shape of
            Open -> 1 / 20
            OpenSliver -> 1 / 100000000
            Crossed -> 1 / 100
            CrossedSliver -> 1 / 100000000
            WrongSide -> -(1 / 100)
            _ -> 0
          expected = pi - 2 * atan t
      length hinges `shouldBe` 2
      forM_ hinges $ \h -> do
        (angle, _) <- right (hingeAngle h points)
        abs (angleError angle expected) `shouldSatisfy` (< 1e-12)
      closedHinges fixture `shouldSatisfy` any ((== PanelBend) . hingeRole)

  it "compares raw contact gaps with the profile and retains the tolerance-sized counterexample" $
    forM_ [1, 2] $ \n -> forM_ [minBound .. maxBound] $ \shape -> do
      fixture <- right (closedCrease n shape)
      let mesh = closedMesh fixture
          orders = [(FaceId 0, FaceId 1)]
          direction = V3 0 0 1
          idealGap = fromRational (minimum (map snd (profileGaps fixture)))
      report <- right (checkTriangleContact direction orders (closedOwners fixture) mesh)
      rows <- right (Contact.prepareContact 0 direction orders (closedOwners fixture) mesh >>= (`Contact.orderedContacts` mesh))
      abs (minimum (0 : map contactGap rows) - idealGap) `shouldSatisfy` (< 1e-12)
      contactPassed report `shouldBe` (shape `notElem` [Crossed, WrongSide])
      null (crossingPanels report) `shouldBe` (shape /= Crossed)
      when (shape == CrossedSliver) $ do
        idealGap `shouldSatisfy` (< 0)
        abs idealGap `shouldSatisfy` (< panelTolerance)
        profileCrossings fixture `shouldSatisfy` (not . null)

  it "exports the same mesh with two source panels and one subdivided source crease" $
    forM_ [minBound .. maxBound] $ \shape -> do
      fixture <- right (closedCrease 1 shape)
      surface <- right (closedSurface fixture)
      surfaceSamples surface `shouldBe` samples (closedMesh fixture)
      let frame = materialFrame surface
      KM.lookup "senbazuru:source_panels" (frameExtras frame) `shouldBe` Just (toJSON (map unFaceId (closedOwners fixture)))
      facesVertices frame `shouldBe` [map VertexId [a, b, c] | (a, b, c) <- triangles (closedMesh fixture)]
      length (filter (== Valley) (edgesAssignment frame)) `shouldBe` 2
      edgesAssignment frame `shouldSatisfy` all (`elem` [Border, Join, Valley])

  it "refuses unsupported subdivisions as values" $
    forM_ [-1, 0, 9] $
      \n -> closedCrease n Open `shouldSatisfy` isLeft

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
