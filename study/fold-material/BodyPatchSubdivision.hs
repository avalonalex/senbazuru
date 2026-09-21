-- | Refine a recovered position without resetting its material or its creases.
-- A panel may already be bent, so subdivide its CURRENT triangles, not a new
-- fan across the original panel. Shared midpoint ids come from Surface's
-- existing refinement. Coincident layers remain separate material vertices.
--
-- The independently constructed fine fixture supplies rest coordinates,
-- physical crease preferences and contact orders. Require exact agreement
-- with that fixture before borrowing its constraints. Subdivision preserves
-- the piecewise planar shape; it does not certify equilibrium or a motion.
-- See docs/glossary.md for material coordinates, panels and rest angles.
module BodyPatchSubdivision (subdivideRecovered, seedPassed) where

import BodyPatch
import Control.Monad (unless)
import CraneSpread
import Data.Bifunctor (first)
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import Senbazuru.Explain (explain)
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

subdivideRecovered :: BodyPatch -> BodyPatch -> MaterialMesh -> Either SpreadError MaterialMesh
subdivideRecovered coarse fine mesh = do
  unless
    ( patchLevel coarse == 0
        && patchLevel fine == 1
        && patchDegrees coarse == patchDegrees fine
        && patchFaces coarse == patchFaces fine
        && patchCore coarse == patchCore fine
        && patchEdges coarse == patchEdges fine
        && patchVertices coarse == patchVertices fine
        && patchMarks coarse == patchMarks fine
        && spreadPins source == spreadPins target
        && spreadOrders source == spreadOrders target
    )
    (Left (SpreadError "recovered subdivision needs matching coarse and fine body-patch fixtures"))
  sheet <- spreadSurface source mesh
  split <- first (SpreadError . explain) (refineSurfaceWithEdges 1 sheet)
  let inherited = refinedMesh split
      expected = refinedMesh (spreadRefined target)
      owners = concatMap (replicate 4) (refinedPanels (spreadRefined source))
  unless
    ( triangles inherited == triangles expected
        && map sampleMaterial (samples inherited) == map sampleMaterial (samples expected)
        && owners == refinedPanels (spreadRefined target)
    )
    (Left (SpreadError "recovered subdivision differs from the fine reference material or panel identities"))
  pure inherited
  where
    source = patchSpread coarse
    target = patchSpread fine

-- | Passing geometry permits a bounded continuation, not acceptance as settled
-- paper. Recheck even though the parent passed: changing triangles changes
-- which contact pairs the independent checker inspects.
seedPassed :: BodyPatch -> MaterialMesh -> Either SpreadError Bool
seedPassed study mesh = do
  contact <- spreadCheck (patchSpread study) mesh
  pure (componentCount mesh == 1 && spreadHeldError (patchSpread study) mesh == 0 && maxLengthError mesh <= 1e-5 && contactPassed contact)
