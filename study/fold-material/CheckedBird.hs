-- | Continue the first checked petal to a bird base: hold the front flap at
-- 175 degrees, lift the back flap, then press both flat. A petal is a pointed
-- flap made by lifting its tip while bringing both sides inward; the two
-- petals move on opposite sides of the stationary square-base packet.
--
-- This module composes three known paths, not arbitrary instructions. The
-- first certificate covers 0--180, so its 0--175 prefix is safe. The second
-- covers 0--180 with the first held at 175. The press certificate covers both
-- hinges moving together through 0--180; we use its 175--180 suffix. Nothing
-- is interpolated between vertex positions. Every pose comes from compatible
-- crease angles and is compared with the exact ideal path within 1e-12 model
-- units. See docs/notes/checked-bird-base.md for the endpoint and join checks.
module CheckedBird
  ( CheckedBird,
    BirdStage (..),
    prepareBird,
    birdChecks,
    birdHinges,
    checkedBirdAt,
    checkedBirdFrame,
    checkedBirdSurface,
    birdStates,
    birdFile,
  )
where

import CheckedPetal (birdAngles, checkedPetalAt, petalCheck, preparePetal)
import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showFFloat)
import PetalCertificate
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface (Surface, materialFrame, withFaceOrders)
import StudyCase

data BirdStage = FrontPetal | BackPetal | PressPetals
  deriving stock (Eq, Show)

-- The source and requirements cannot change after preparation. Every stage
-- shares the same material anchor and the orders accepted by the first fold.
data CheckedBird = CheckedBird !CaseSpec !Frame ![(BirdStage, PetalCertificate)]
  deriving stock (Show)

birdChecks :: CheckedBird -> [(BirdStage, PetalCertificate)]
birdChecks (CheckedBird _ _ reports) = reports

prepareBird :: CaseSpec -> Frame -> Either Text CheckedBird
prepareBird spec source = do
  firstPetal <- preparePetal spec source
  accepted <- checkedPetalAt firstPetal 175
  (_, orders) <- maybe (Left "bird sequence needs the first petal's accepted orders") Right (poseOrders accepted)
  back <- certifySecondPetal True orders
  pressing <- certifyPress True orders
  let checked = CheckedBird spec source [(FrontPetal, petalCheck firstPetal), (BackPetal, back), (PressPetals, pressing)]
  next <- checkedBirdAt checked BackPetal 0
  checkJoin accepted next
  backEnd <- checkedBirdAt checked BackPetal 1
  pressStart <- checkedBirdAt checked PressPetals 0
  checkJoin backEnd pressStart
  _ <- checkedBirdAt checked FrontPetal 0
  _ <- checkedBirdAt checked PressPetals 1
  pure checked

-- | Progress is a fraction of the stage's hinge-angle range. The other six
-- crease angles in each petal follow its closure formula, not that fraction.
birdHinges :: BirdStage -> Double -> (Double, Double)
birdHinges FrontPetal fraction = (175 * fraction, 0)
birdHinges BackPetal fraction = (175, 175 * fraction)
birdHinges PressPetals fraction = let t = 175 + 5 * fraction in (t, t)

birdPose :: BirdStage -> Double -> PoseSpec
birdPose stage fraction =
  let (t, u) = birdHinges stage fraction
      title = case stage of
        FrontPetal | fraction == 0 -> "Square base · start with the top flap"
        FrontPetal -> "Front petal · " <> degreesText t <> "°"
        BackPetal -> "Back petal · " <> degreesText u <> "° beneath the packet"
        PressPetals | fraction == 1 -> "Bird base · both petals flat"
        PressPetals -> "Press both petals · " <> degreesText t <> "°"
   in PoseSpec title (birdAngles t u)

-- Labels need a readable angle; the exported numeric angles retain precision.
degreesText :: Double -> Text
degreesText t = T.pack (showFFloat (Just 1) t "")

checkedBirdAt :: CheckedBird -> BirdStage -> Double -> Either Text StudyPose
checkedBirdAt (CheckedBird spec source _) stage fraction = do
  unless (not (isNaN fraction || isInfinite fraction) && fraction >= 0 && fraction <= 1) (Left "bird stage progress must be finite and between 0 and 1")
  pose <- first explain (buildCasePose 0 spec source (birdPose stage fraction))
  points <- first explain (frameVertices (poseFrame pose))
  let (t, u) = birdHinges stage fraction
  unless (samePoints points (birdPoints t u)) (Left "angle-derived bird differs from the certified path")
  unless (maybe False contactPassed (poseContact pose)) (Left "bird pose failed contact or layer-order checks")
  pure pose

checkJoin :: StudyPose -> StudyPose -> Either Text ()
checkJoin before after = do
  let a = poseFrame before
      b = poseFrame after
  pa <- first explain (frameVertices a)
  pb <- first explain (frameVertices b)
  unless (samePoints pa pb && edgesFoldAngle a == edgesFoldAngle b && edgesVertices a == edgesVertices b && facesVertices a == facesVertices b && poseOrders before == poseOrders after) (Left "bird stage join changed geometry, angles, topology or accepted layer order")
  unless (frameExtras (materialFrame (poseSurface before)) == frameExtras (materialFrame (poseSurface after))) (Left "bird stage join changed original material coordinates")

samePoints :: [V3] -> [V3] -> Bool
samePoints as bs = length as == length bs && and (zipWith (\a b -> norm (a ^-^ b) < 1e-12) as bs)

checkedBirdFrame :: CheckedBird -> BirdStage -> Double -> Either Text Frame
checkedBirdFrame checked@(CheckedBird spec source _) stage fraction = do
  pose <- checkedBirdAt checked stage fraction
  frame <- first explain (buildCaseFrame spec source (birdPose stage fraction))
  paper <- first explain (withFaceOrders (faceOrders frame) (poseSurface pose))
  pure frame {frameExtras = frameExtras (materialFrame paper)}

checkedBirdSurface :: CheckedBird -> BirdStage -> Double -> Either Text (Surface V2)
checkedBirdSurface checked stage fraction = do
  pose <- checkedBirdAt checked stage fraction
  frame <- checkedBirdFrame checked stage fraction
  first explain (withFaceOrders (faceOrders frame) (poseSurface pose))

-- | Sixteen figures with joins shown once, including an intermediate press.
birdStates :: [(BirdStage, Double)]
birdStates = [(FrontPetal, t / 175) | t <- [0, 30, 60, 90, 120, 150, 175]] ++ [(BackPetal, t / 175) | t <- [15, 30, 60, 90, 120, 150, 175]] ++ [(PressPetals, 0.5), (PressPetals, 1)]

birdFile :: CheckedBird -> Either Text FoldFile
birdFile checked = do
  frames <- traverse (uncurry (checkedBirdFrame checked)) birdStates
  pure (FoldFile (Just 1.2) (Just "senbazuru continuously checked bird base") Nothing (Just "Two petals from the square base") Nothing ["diagrams"] emptyFrame frames)
