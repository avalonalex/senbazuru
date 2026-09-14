-- | Keep the expensive crane out of this contact regression. Exact clipping
-- tests include a warped middle row that an outer-edge profile would miss.
module CreaseCorrectionSpec (spec) where

import ClosedCrease
import Control.Monad (forM_)
import CreaseCorrection
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldRelaxation
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec hiding (after, before)
import WingBending (finalMesh)

spec :: Spec
spec = describe "contact correction beside a shared crease" $ do
  it "keeps matched material, fixed lower panel, crease and outer upper strip" $
    forM_ [1, 2] $ \n -> do
      ordinary <- right (creaseCorrection n PenetratingGuess)
      disabled <- right (creaseCorrection n WithoutContact)
      correctionSeed ordinary `shouldBe` correctionSeed disabled
      correctionPins ordinary `shouldBe` correctionPins disabled
      forM_ [minBound .. maxBound] $ \control -> do
        fixture <- right (creaseCorrection n control)
        let seed = correctionSeed fixture
            reference = closedMesh (correctionReference fixture)
            actual = IM.fromList (zip [0 ..] (map position (samples seed)))
        triangles seed `shouldBe` triangles reference
        map sampleMaterial (samples seed) `shouldBe` map sampleMaterial (samples reference)
        forM_ (IM.toList (correctionPins fixture)) $ \(i, p) -> IM.lookup i actual `shouldBe` Just p
        forM_ (closedRoot (correctionReference fixture)) $ \i -> IM.member i (correctionPins fixture) `shouldBe` True
        audit <- right (auditLowerGap fixture seed)
        if control == ReferenceStart
          then minimumGap audit `shouldBe` 0
          else minimumGap audit `shouldSatisfy` (< 0)

  it "agrees with the prescribed profiles without assuming the corrected upper remains extruded" $
    forM_ [1, 2] $ \n -> do
      fixture <- right (creaseCorrection n ReferenceStart)
      forM_ [BentTouching, Open, OpenSliver, Crossed, CrossedSliver, WrongSide] $ \shape -> do
        posed <- right (closedCrease n shape)
        audit <- right (auditLowerGap fixture (closedMesh posed))
        let ideal = minimum (map snd (profileGaps posed))
        abs (fromRational (minimumGap audit - ideal) :: Double) `shouldSatisfy` (< 1e-15)
      let original = correctionSeed fixture
          middle p = materialU p == -0.25 && materialV p == 0
          warped = original {samples = [if middle p then let V3 x y z = position p in p {position = V3 x (y + 0.03) (z - 0.0001)} else p | p <- samples original]}
      gap <- right (auditLowerGap fixture warped)
      minimumGap gap `shouldSatisfy` (< -(1 / 100000))
      -- The two outside rows still coincide with the lower panel exactly.
      [p | p <- samples warped, abs (materialV p) == 0.5] `shouldBe` [p | p <- samples original, abs (materialV p) == 0.5]

  it "refuses changed material, a moved lower reference or non-finite positions" $ do
    fixture <- right (creaseCorrection 1 ReferenceStart)
    let mesh = correctionSeed fixture
        alter f = mesh {samples = zipWith (\i p -> if i == 0 then f p else p) [0 :: Int ..] (samples mesh)}
    auditLowerGap fixture (alter (\p -> p {sampleMaterial = V2 99 99})) `shouldSatisfy` isLeft
    auditLowerGap fixture (alter (\p -> p {position = V3 0 0 0.001})) `shouldSatisfy` isLeft
    auditLowerGap fixture (alter (\p -> p {position = V3 (0 / 0) 0 0})) `shouldSatisfy` isLeft
    correctionSurface fixture mesh {triangles = []} `shouldSatisfy` isLeft

  it "greatly reduces penetration but retains the negative exact residual" $ do
    fixture <- right (creaseCorrection 1 PenetratingGuess)
    before <- right (auditLowerGap fixture (correctionSeed fixture))
    (result, _) <- right (solveCorrection (Settings 40 1e-5) fixture)
    mesh <- right (finalMesh result)
    after <- right (auditLowerGap fixture mesh)
    contact <- right (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners (correctionReference fixture)) mesh)
    converged result `shouldBe` True
    maxLengthError mesh `shouldSatisfy` (< 1e-5)
    contactPassed contact `shouldBe` True
    minimumGap after `shouldSatisfy` (< 0)
    abs (minimumGap after) `shouldSatisfy` (< abs (minimumGap before) / 1000000)
    let points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    forM_ (IM.toList (correctionPins fixture)) $ \(i, p) -> IM.lookup i points `shouldBe` Just p
    exported <- right (correctionSurface fixture mesh)
    surfaceSamples exported `shouldBe` samples mesh

  it "does not equate numerical convergence without contact with a correct layer order" $ do
    fixture <- right (creaseCorrection 1 WithoutContact)
    (result, _) <- right (solveCorrection (Settings 40 1e-5) fixture)
    mesh <- right (finalMesh result)
    audit <- right (auditLowerGap fixture mesh)
    converged result `shouldBe` True
    minimumGap audit `shouldSatisfy` (< -(1 / 10000))

  it "cannot repair an upper hold installed through the fixed lower panel" $ do
    fixture <- right (creaseCorrection 1 ConflictingHold)
    (result, _) <- right (solveCorrection (Settings 40 1e-5) fixture)
    mesh <- right (finalMesh result)
    audit <- right (auditLowerGap fixture mesh)
    converged result `shouldBe` False
    minimumGap audit `shouldSatisfy` (<= -(1 / 1000))
    let points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    forM_ (IM.toList (correctionPins fixture)) $ \(i, p) -> IM.lookup i points `shouldBe` Just p

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
