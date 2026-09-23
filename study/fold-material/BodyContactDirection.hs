-- | Ask a body correction to avoid worsening one pair's contact before the
-- nonlinear search. A witness is a corner of the triangles' projected overlap;
-- its signed gap is positive when the declared upper layer is above the lower.
-- SurfaceContact differentiates that corner as well as the two moving planes.
--
-- A saved passing shape can have a tiny negative gap. The incremental guard
-- preserves its existing floor min(0,g), so a*d + max(0,g) >= 0 is feasible
-- at zero correction. This is NOT a repair or a changed contact tolerance:
-- negative gaps still contribute their full original penalty to the objective.
-- New clipping corners and other triangle pairs still need the independent
-- nonlinear geometry check. See docs/notes/body-contact-direction.md.
module BodyContactDirection (contactGuard, directionRows) where

import ContactQuadratic (QuadraticRow)
import CraneSpread (SpreadError (..))
import CreaseInequality (materialRows)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import FoldBending (Hinge)
import FoldContact (ContactRow (..))
import FoldMaterial (meshEdges)
import Senbazuru.Explain (explain)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh)
import SurfaceContact

contactGuard :: IM.IntMap V3 -> ContactRow -> QuadraticRow
contactGuard pins row = (IM.difference (IM.fromListWith (^+^) (contactGradient row)) pins, max 0 (contactGap row))

-- | Same final-weight material quadratic as the archived penalty solve,
-- including ALL negative gaps, even those below the stopping tolerance.
-- Keep lengths, contacts, then angles in the original row order. Exact holds
-- have zero displacement and are removed from every gradient.
directionRows :: [Hinge] -> IM.IntMap V3 -> OrderedContact -> MaterialMesh -> Either SpreadError [QuadraticRow]
directionRows hinges pins model mesh = do
  rows <- first (SpreadError . explain) (materialRows hinges pins 1e8 mesh)
  contacts <- first (SpreadError . explain) (orderedContacts model mesh)
  let (lengths, angles) = splitAt (length (meshEdges mesh)) rows
      penalties = [(IM.map (1e5 *^) (fst (contactGuard pins row)), 1e5 * contactGap row) | row <- contacts, contactGap row < 0]
  pure (lengths ++ penalties ++ angles)
