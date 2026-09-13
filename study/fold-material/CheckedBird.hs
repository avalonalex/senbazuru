-- | One known route from a prepared open square to the bird base. First six
-- meeting creases collapse together into a layered square; then the front
-- petal reaches 175 degrees, the back petal lifts underneath, and both press
-- flat. A petal is a pointed flap made by lifting its tip while bringing its
-- sides inward. See docs/notes/checked-square-collapse.md for the initial fold
-- and docs/notes/checked-bird-base.md for the two petals.
--
-- This module composes four certified paths, not arbitrary instructions.
-- The collapse uses its full interval. Each separate petal uses a 0--175
-- prefix of a full 0--180 turn; the simultaneous press uses its 175--180
-- suffix. Every pose comes from compatible crease angles and is compared
-- with the ideal path within 1e-12 model units. No vertex interpolation is
-- involved. The constructor is hidden so the material, anchor and accepted
-- endpoint orders cannot change underneath the certificates.
module CheckedBird
  ( CheckedBird,
    BirdStage (..),
    prepareBird,
    birdChecks,
    birdHinges,
    collapseAngles,
    checkedBirdAt,
    checkedBirdFrame,
    checkedBirdSurface,
    birdStates,
    birdFile,
  )
where

import CheckedPetal (birdAngles, checkedPetalAt, petalCheck, preparePetal)
import ContactSpec (ContactSpec (..))
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

data BirdStage = SquareCollapse | FrontPetal | BackPetal | PressPetals
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
  collapse <- certifyCollapse True orders
  back <- certifySecondPetal True orders
  pressing <- certifyPress True orders
  let checked = CheckedBird spec source [(SquareCollapse, collapse), (FrontPetal, petalCheck firstPetal), (BackPetal, back), (PressPetals, pressing)]
  collapsed <- checkedBirdAt checked SquareCollapse 1
  frontStart <- checkedBirdAt checked FrontPetal 0
  checkJoin collapsed frontStart
  _ <- checkedBirdAt checked SquareCollapse 0
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
birdHinges SquareCollapse _ = (0, 0)
birdHinges FrontPetal fraction = (175 * fraction, 0)
birdHinges BackPetal fraction = (175, 175 * fraction)
birdHinges PressPetals fraction = let t = 175 + 5 * fraction in (t, t)

birdPose :: BirdStage -> Double -> PoseSpec
birdPose SquareCollapse fraction =
  let m = 180 * fraction
      label
        | fraction == 0 = "Open sheet · collapse the prepared creases"
        | fraction == 1 = "Square base · ready for the first petal"
        | otherwise = "Collapse · diagonal " <> degreesText m <> "°"
   in PoseSpec label (collapseAngles m)
birdPose stage fraction =
  let (t, u) = birdHinges stage fraction
      title = case stage of
        FrontPetal | fraction == 0 -> "Square base · start with the top flap"
        FrontPetal -> "Front petal · " <> degreesText t <> "°"
        BackPetal -> "Back petal · " <> degreesText u <> "° beneath the packet"
        PressPetals | fraction == 1 -> "Bird base · both petals flat"
        PressPetals -> "Press both petals · " <> degreesText t <> "°"
   in PoseSpec title (birdAngles t u)

-- | Two diagonal valleys turn by m; four midline mountains must turn
-- farther to keep the centre joined. The petal creases stay flat. At 180
-- this is exactly birdAngles 0 0, including the same material edge ids.
collapseAngles :: Double -> [Double]
collapseAngles m =
  let half = m * pi / 360
      v = if m == 180 then 180 else 360 / pi * atan2 (sqrt 2 * sin half) (cos half)
   in replicate 8 0 ++ [m, m, -v, -v, 0, 0, -v, -v, 0, 0, -v, -v, 0, 0, -v, -v, 0, 0, 0, 0]

-- Labels need a readable angle; the exported numeric angles retain precision.
degreesText :: Double -> Text
degreesText t = T.pack (showFFloat (Just 1) t "")

checkedBirdAt :: CheckedBird -> BirdStage -> Double -> Either Text StudyPose
checkedBirdAt (CheckedBird spec source _) stage fraction = do
  unless (not (isNaN fraction || isInfinite fraction) && fraction >= 0 && fraction <= 1) (Left "bird stage progress must be finite and between 0 and 1")
  pose <- first explain (buildCasePose 0 (stageSpec spec stage fraction) source (birdPose stage fraction))
  points <- first explain (frameVertices (poseFrame pose))
  let (t, u) = birdHinges stage fraction
  let expected = if stage == SquareCollapse then collapsePoints (180 * fraction) else birdPoints t u
  unless (samePoints points expected) (Left "angle-derived bird differs from the certified path")
  unless (maybe False contactPassed (poseContact pose)) (Left "bird pose failed contact or layer-order checks")
  pure pose

-- During collapse there is no area contact: the certificate separates every
-- panel interior. A flat landing order is not an order between shadows cast
-- by tilted panels. Keep static intersection checks, then attach the already
-- certified landing requirements when the packet actually reaches contact.
stageSpec :: CaseSpec -> BirdStage -> Double -> CaseSpec
stageSpec spec SquareCollapse fraction | fraction < 1 = spec {caseContact = fmap (\contact -> contact {panelOrders = []}) (caseContact spec)}
stageSpec spec _ _ = spec

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
  frame <- first explain (buildCaseFrame (stageSpec spec stage fraction) source (birdPose stage fraction))
  paper <- first explain (withFaceOrders (faceOrders frame) (poseSurface pose))
  pure frame {frameExtras = frameExtras (materialFrame paper)}

checkedBirdSurface :: CheckedBird -> BirdStage -> Double -> Either Text (Surface V2)
checkedBirdSurface checked stage fraction = do
  pose <- checkedBirdAt checked stage fraction
  frame <- checkedBirdFrame checked stage fraction
  first explain (withFaceOrders (faceOrders frame) (poseSurface pose))

-- | Twenty-three figures with joins shown once, including the open sheet.
birdStates :: [(BirdStage, Double)]
birdStates = [(SquareCollapse, m / 180) | m <- [0, 30, 60, 90, 120, 150, 175, 180]] ++ [(FrontPetal, t / 175) | t <- [30, 60, 90, 120, 150, 175]] ++ [(BackPetal, t / 175) | t <- [15, 30, 60, 90, 120, 150, 175]] ++ [(PressPetals, 0.5), (PressPetals, 1)]

birdFile :: CheckedBird -> Either Text FoldFile
birdFile checked = do
  frames <- traverse (uncurry (checkedBirdFrame checked)) birdStates
  pure (FoldFile (Just 1.2) (Just "senbazuru continuously checked bird base") Nothing (Just "From the open sheet to a bird base") Nothing ["diagrams"] emptyFrame frames)
