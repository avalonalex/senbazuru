-- | Bind the ideal first-petal certificate to the existing bird FOLD fixture.
-- A petal opens two old folds while four side folds and its tip hinge turn
-- together; see docs/notes/petal-fold-motion.md. This remains a study recipe:
-- it accepts the known material/topology, not an arbitrary coupled crease.
--
-- The constructor is hidden. Every returned pose is derived by Folding from
-- seven compatible angles, checked for shared vertices and achieved angles,
-- compared with the certified path within 1e-12 of the unit sheet, and checked
-- for contact. The exact certificate covers the ideal path BETWEEN poses.
module CheckedPetal
  ( CheckedPetal,
    preparePetal,
    petalCheck,
    checkedPetalAt,
    checkedPetalFrame,
    checkedPetalSurface,
    petalAngles,
    petalStates,
    petalFile,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (bimap, first)
import Data.Text (Text)
import PetalCertificate
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Senbazuru.Origami.Surface (Surface, materialFrame, withFaceOrders)
import StudyCase

-- Keep the accepted case and source private: a certificate cannot be reused
-- after changing the sheet, the angle rule, its anchor, or its layer order.
data CheckedPetal = CheckedPetal !CaseSpec !Frame !PetalCertificate
  deriving stock (Show)

petalCheck :: CheckedPetal -> PetalCertificate
petalCheck (CheckedPetal _ _ report) = report

preparePetal :: CaseSpec -> Frame -> Either Text CheckedPetal
preparePetal spec source = do
  material <- first explain (frameVertices source)
  unless (samePoints material petalMaterial) (Left "checked petal requires the material vertices of examples/bird-base.fold")
  traced <- first explain (foldFrameWith source {edgesFoldAngle = petalAngles 0})
  unless (map (map unVertexId) (facesVertices (foldedPattern traced)) == petalFaces && edgesVertices (foldedPattern traced) == expectedEdges) (Left "checked petal requires the bird fixture's cut faces and edge ids")
  unless (caseFixedPanel spec == Just (0.58, 0.4)) (Left "checked petal requires the stationary base anchor")
  start <- checkedPose spec source 0
  (axis, orders) <- maybe (Left "checked petal requires layer orders") Right (poseOrders start)
  unless (axis == V3 0 0 1) (Left "checked petal orders must point above the stationary packet")
  report <- certifyPetal True orders
  let result = CheckedPetal spec source report
  _ <- checkedPetalAt result 180
  pure result
  where
    expectedEdges = map (bimap VertexId VertexId) [(0, 4), (4, 1), (1, 5), (5, 2), (2, 6), (6, 3), (3, 7), (7, 0), (0, 8), (8, 2), (8, 9), (9, 4), (9, 0), (9, 1), (8, 10), (10, 5), (10, 1), (10, 2), (8, 11), (11, 6), (11, 2), (11, 3), (8, 12), (12, 7), (12, 3), (12, 0), (9, 10), (11, 12)]

checkedPetalAt :: CheckedPetal -> Double -> Either Text StudyPose
checkedPetalAt (CheckedPetal spec source _) = checkedPose spec source

checkedPose :: CaseSpec -> Frame -> Double -> Either Text StudyPose
checkedPose spec source degrees = do
  unless (not (isNaN degrees || isInfinite degrees) && degrees >= 0 && degrees <= 180) (Left "petal angle must be finite and between 0 and 180 degrees")
  pose <- first explain (buildCasePose 0 spec source (PoseSpec (title degrees) (petalAngles degrees)))
  points <- first explain (frameVertices (poseFrame pose))
  unless (samePoints points (petalPoints degrees)) (Left "angle-derived petal differs from the certified path")
  unless (maybe False contactPassed (poseContact pose)) (Left "petal pose failed contact or layer-order checks")
  pure pose

-- | Export through the existing FOLD boundary, which retains only currently
-- coplanar orders and activates formerly flat creases. Validate that this is
-- a pose of the certified motion before returning its ordinary FOLD frame.
checkedPetalFrame :: CheckedPetal -> Double -> Either Text Frame
checkedPetalFrame checked@(CheckedPetal spec source _) degrees = do
  pose <- checkedPetalAt checked degrees
  frame <- first explain (buildCaseFrame spec source (PoseSpec (title degrees) (petalAngles degrees)))
  paper <- first explain (withFaceOrders (faceOrders frame) (poseSurface pose))
  pure frame {frameExtras = frameExtras (materialFrame paper)}

-- | Rendering needs the coplanar FOLD orders as well as the directional
-- material requirements. Preserve the original material samples when adding
-- them; rebuilding a surface from folded coordinates would lose that identity.
checkedPetalSurface :: CheckedPetal -> Double -> Either Text (Surface V2)
checkedPetalSurface checked degrees = do
  pose <- checkedPetalAt checked degrees
  frame <- checkedPetalFrame checked degrees
  first explain (withFaceOrders (faceOrders frame) (poseSurface pose))

samePoints :: [V3] -> [V3] -> Bool
samePoints as bs = length as == length bs && and (zipWith (\a b -> norm (a ^-^ b) < 1e-12) as bs)

petalAngles :: Double -> [Double]
petalAngles t =
  let half = t * pi / 360
      s = if t == 180 then 180 else 360 / pi * atan2 (sin (pi / 8) * sin half) (cos half)
   in replicate 8 0 ++ [180, 180, -180, t - 180, -s, -s, -180, t - 180, -s, -s, -180, -180, 0, 0, -180, -180, 0, 0, t, 0]

title :: Double -> Text
title 0 = "Square base · start with the top flap"
title 180 = "One petal complete · press the sides flat"
title t = "Lift the tip · " <> tshow t <> "°"

petalStates :: [Double]
petalStates = [0, 30, 60, 90, 120, 150, 175, 180]

petalFile :: CheckedPetal -> Either Text FoldFile
petalFile checked = do
  frames <- traverse (checkedPetalFrame checked) petalStates
  pure (FoldFile (Just 1.2) (Just "senbazuru continuously checked bird petal") Nothing (Just "One bird petal from the square base") Nothing ["diagrams"] emptyFrame frames)
