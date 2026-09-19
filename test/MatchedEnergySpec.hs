-- | Material-edge comparisons on authored and analytic shapes. No optimizer
-- is needed to check conservation of the reported spring costs or the archive
-- boundary; these fixtures are not evidence of an equilibrium solution.
module MatchedEnergySpec (spec) where

import BandBoundary
import BendLocations
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (isJust, isNothing)
import Data.String (fromString)
import Data.Text (Text)
import FoldBending
import MatchedEnergy
import OuterStrip
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "saved matched energy locations" $ do
  it "accounts for every edge across all four meshes, both panels and directions" $ do
    fixtures <- mapM (\(c, _, _) -> (c,) <$> rowsFor c) outerMeshes
    forM_ [(a, b) | (ca, a) <- fixtures, (cb, b) <- fixtures, (ca, cb) `elem` outerPairs] $ \(ra, rb) ->
      forM_ [False, True] $ \upper -> do
        let a = filter ((== upper) . measuredUpper . locatedMeasure) ra
            b = filter ((== upper) . measuredUpper . locatedMeasure) rb
        changes <- right (compareBends a b)
        length [c | c <- changes, isJust (oldBend c)] `shouldBe` length a
        length [c | c <- changes, isJust (newBend c)] `shouldBe` length b
        let delta = sum (map (measuredEnergy . locatedMeasure) b) - sum (map (measuredEnergy . locatedMeasure) a)
            shared = [c | c <- changes, isJust (oldBend c), isJust (newBend c)]
            unmatched = [c | c <- changes, isNothing (oldBend c) || isNothing (newBend c)]
        near (sum (map edgeDelta changes)) delta
        near (sum [coefficientPart c + anglePart c | c <- shared] + sum (map edgeDelta unmatched)) delta
        sum [bendEnergy (newBend c) | c <- changes, edgeDirection (changeLocation c) == "Diagonal"] `shouldSatisfy` (> 1e-8)
        reversed <- right (compareBends b a)
        forM_ (zip changes reversed) $ \(c, d) -> do
          near (edgeDelta c) (negate (edgeDelta d))
          near (coefficientPart c) (negate (coefficientPart d))
          near (anglePart c) (negate (anglePart d))

  it "uses material endpoints rather than ids or edge orientation" $ do
    rows <- rowsFor Coarse
    let renumber h = h {locatedFrom = locatedTo h, locatedTo = locatedFrom h, locatedMeasure = let m = locatedMeasure h; spring = measuredHinge m in m {measuredHinge = spring {hingeVertices = (400, 300, 200, 100)}}}
    changes <- right (compareBends rows (map renumber (reverse rows)))
    length changes `shouldBe` length rows
    forM_ changes $ \c -> do
      isJust (oldBend c) && isJust (newBend c) `shouldBe` True
      edgeDelta c `shouldBe` 0

  it "distinguishes absent springs from zero-cost springs and rejects duplicates or invalid costs" $ do
    fixture <- right (prescribedFixture 2 1 FlatPanels)
    rows <- passive <$> right (locateBends fixture)
    added <- right (compareBends [] rows)
    removed <- right (compareBends rows [])
    length added `shouldBe` length rows
    all (isNothing . oldBend) added `shouldBe` True
    all (isNothing . newBend) removed `shouldBe` True
    sum (map edgeDelta added) `shouldBe` 0
    compareBends (rows ++ rows) [] `shouldSatisfy` isLeft
    case rows of
      h : _ -> do
        let m = locatedMeasure h; spring = measuredHinge m
        forM_ [h {locatedTo = locatedFrom h}, h {locatedMeasure = m {measuredAngle = 0 / 0}}, h {locatedMeasure = m {measuredEnergy = 1}}, h {locatedMeasure = m {measuredHinge = spring {hingeRest = 0.1}}}, h {locatedMeasure = m {measuredHinge = spring {hingeRole = BendControl}}}] $ \bad -> compareBends [bad] [] `shouldSatisfy` isLeft
      _ -> expectationFailure "expected passive flat springs"

  it "requires unique, converged matched archives with the original policy" $
    forM_ outerMeshes $ \(choice, key, _) -> do
      f <- right (outerFixture choice OriginalTurns MatchedHolds)
      forM_ ["original", "fractional"] $ \rule -> do
        let r = archiveRun choice key rule f
            doc :: [Value] -> Value
            doc rs = object ["gallery" .= ("outer-strip" :: String), "runs" .= rs]
            readOne = matchedRecord choice (fromString key) rule f
            set k v (Object o) = Object (KM.insert k v o)
            set _ _ v = v
        readOne (doc [r]) `shouldBe` Right r
        readOne (doc [r, r]) `shouldSatisfy` isLeft
        readOne (doc []) `shouldSatisfy` isLeft
        forM_ [set "passed" (Bool False) r, set "solve" (object ["converged" .= False]) r, set "heldVertices" (Array mempty) r, set "contactEnabled" (Bool False) r, set "lengthTolerance" (Number 0.001) r, set "columns" (Array mempty) r, set "control" (String "band") r] $ \bad -> readOne (doc [bad]) `shouldSatisfy` isLeft

rowsFor :: OuterMesh -> IO [LocatedBend]
rowsFor choice = do
  fixture <- right (outerFixture choice OriginalTurns MatchedHolds)
  let reference = coupledReference fixture
      mesh = closedMesh reference
      bend p = let d = abs (materialU p); v = materialV p; V3 x y z = cylinderPoint d v in p {position = V3 x y (z + 0.005 * d * (0.25 - v * v))}
  passive <$> right (locateBends reference {closedMesh = mesh {samples = map bend (samples mesh)}})

passive :: [LocatedBend] -> [LocatedBend]
passive = filter ((== PanelBend) . hingeRole . measuredHinge . locatedMeasure)

archiveRun :: OuterMesh -> String -> Text -> CoupledFixture -> Value
archiveRun choice key rule f =
  object
    [ "id" .= ("matched-" <> fromString key <> "-" <> rule),
      "meshKey" .= key,
      "rule" .= rule,
      "control" .= ("matched" :: String),
      "contactEnabled" .= True,
      "contactMethod" .= ("ProgressiveContactExchange" :: String),
      "lengthWeights" .= ([1e2, 1e4, 1e6, 1e8, 1e9, 1e10] :: [Double]),
      "iterationLimitPerStage" .= (40 :: Int),
      "lengthTolerance" .= (1e-5 :: Double),
      "columns" .= map (fromRational :: Rational -> Double) (outerColumns choice),
      "heldVertices" .= IM.keys (coupledPins f),
      "sharedCreaseVertices" .= closedRoot (coupledReference f),
      "vertices" .= length (samples (coupledSeed f)),
      "triangles" .= length (triangles (coupledSeed f)),
      "passed" .= True,
      "refusal" .= Null,
      "solve" .= object ["converged" .= True]
    ]

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
