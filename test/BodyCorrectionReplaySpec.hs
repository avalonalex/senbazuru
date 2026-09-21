-- | The last failing pair in the saved direction, without a solver or archive.
module BodyCorrectionReplaySpec (spec) where

import BodyContactDiagnosis
import BodyCorrectionReplay
import Data.Either (isLeft)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "saved body correction replay" $ do
  it "keeps material identity while halving away the last reported crossing" $ do
    mapM_
      ( \(scale, crosses) -> do
          mesh <- right (scaledProposal scale start proposal)
          triangles mesh `shouldBe` triangles start
          map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples start)
          section <- right (pairSection mesh (0, 1))
          sectionCrosses section `shouldBe` crosses
          report <- right (checkLocalTriangleContact (V3 0 0 1) [(0, 1)] mesh)
          null (crossingPanels report) `shouldBe` not crosses
          reversedOrders report `shouldBe` []
      )
      [(1 / 32, True), (1 / 64, False)]
  it "refuses incomplete or nonfinite numerical proposals and fractions" $ do
    scaledProposal 0.25 start (drop 1 proposal) `shouldSatisfy` isLeft
    scaledProposal 0.25 start (V3 (0 / 0) 0 0 : drop 1 proposal) `shouldSatisfy` isLeft
    mapM_ (\scale -> scaledProposal scale start proposal `shouldSatisfy` isLeft) [-1, 1.1, 1 / 0, 0 / 0]
  it "retains the unchanged-start control and the existing line-search budget" $ do
    scaledProposal 0 start proposal `shouldBe` Right start
    length replayFractions `shouldBe` 31
    take 7 replayFractions `shouldBe` [1, 0.5, 0.25, 0.125, 0.0625, 0.03125, 0.015625]
    drop 30 replayFractions `shouldBe` [2 ** (-30)]

-- Triangles 22 and 63, correction 2 in our generated #322 archive. The six
-- material ids remain distinct. These coordinates exercise geometry, not a
-- material-energy model; the full gallery checks the entire connected sheet.
start :: MaterialMesh
start = Mesh [Sample (V2 (fromIntegral i) 0) p | (i, p) <- zip [0 :: Int ..] positions] [(0, 1, 2), (3, 4, 5)]
  where
    positions =
      [ V3 0.9413444961656986 0.35131549110338844 0.005287591256934788,
        V3 0.8916175162818445 0.4545042431597585 0.01397562781856737,
        V3 0.8826889923315139 0.4097377633932933 0.010575182514462524,
        V3 0.9328039991507575 0.4117064510989494 0.011064122299115098,
        V3 0.8830770192669135 0.4117358644771996 0.010726886184741961,
        V3 0.9502730201160695 0.4992413095484499 0.017713309230728537
      ]

proposal :: [V3]
proposal =
  [ V3 0.9413432765406594 0.3513186648986923 0.0052405164125195036,
    V3 0.8916170001261704 0.45450849737925436 0.013921767774740685,
    V3 0.882687905207373 0.4097444285168345 0.010491215216212244,
    V3 0.9328039133672126 0.4117062431805321 0.011070512886793097,
    V3 0.8830776173038793 0.4117421382103353 0.0106442449125309,
    V3 0.9502732548225947 0.4992448134955826 0.01767066820985746
  ]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
