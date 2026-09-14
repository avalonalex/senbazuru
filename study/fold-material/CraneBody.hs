-- | Test angle preferences on the same small body patch as CraneRoot.
-- The four panels beside one wing root can move; every vertex shared with
-- other panels and the original tip grip remain held. The pocket map supplies
-- candidate opening creases, of which only two touch this released patch.
-- See docs/glossary.md for panels, material coordinates and rest angles.
--
-- The old strict angle limit was an acceptance gate, not a solver constraint.
-- Reclassifying an angle as a preference cannot change the solved positions.
-- Separate that comparison from weaker springs and a 170-degree preference,
-- and measure every original fold against its ORIGINAL target even when a
-- spring's preferred angle changes. Contact and length gates stay unchanged.
module CraneBody
  ( BodyControl (..),
    CraneBody (..),
    BodyAngle (..),
    craneBody,
    bodyAngles,
    bodyAngleErrors,
    bodyAccepted,
  )
where

import Control.Monad (unless)
import CranePocket
import CraneRoot
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

data BodyControl = OriginalPreferences | WeakerBody | OpenBody
  deriving stock (Eq, Show)

data CraneBody = CraneBody
  { bodyRoot :: !CraneRoot,
    bodySelected :: !(S.Set EdgeId),
    bodyOriginalHinges :: ![Hinge],
    bodyControl :: !BodyControl
  }
  deriving stock (Show)

-- | One refined segment of an original crease. Several rows can share a
-- source id: bending next to a crease can make its angle vary along its length.
data BodyAngle = BodyAngle
  { angleSource :: !EdgeId,
    angleSelected :: !Bool,
    angleAchieved :: !Double,
    angleOriginal :: !Double,
    anglePreferred :: !Double
  }
  deriving stock (Eq, Show)

craneBody :: Frame -> Int -> BodyControl -> Either SpreadError CraneBody
craneBody source level control = do
  original <- craneRoot source level FreeBody
  let fixture = rootSpread original
  atlas <- first (SpreadError . explain) (mapCranePocket (spreadSource fixture))
  let selected = S.fromList [creaseId (pocketCrease edge) | edge <- pocketEdges atlas, pocketRole edge == CandidateOpening, any (`S.member` rootNeighbours original) (pocketOwners edge)]
      change hinge = case hingeRole hinge of
        SurfaceCrease eid | S.member eid selected -> case control of
          OriginalPreferences -> hinge
          WeakerBody -> hinge {hingeStiffness = 0.1 * hingeStiffness hinge}
          OpenBody -> hinge {hingeRest = signum (hingeRest hinge) * 170 * pi / 180}
        _ -> hinge
      hinges = spreadHinges fixture
  unless (S.size selected == 2) (Left (SpreadError "expected two mapped opening creases beside the released root patch"))
  pure (CraneBody original {rootSpread = fixture {spreadHinges = map change hinges}} selected hinges control)

bodyAngles :: CraneBody -> MaterialMesh -> Either SpreadError [BodyAngle]
bodyAngles study mesh = mapM measure original
  where
    fixture = rootSpread (bodyRoot study)
    original = [(eid, hinge) | hinge <- bodyOriginalHinges study, SurfaceCrease eid <- [hingeRole hinge], S.notMember eid (rootEdges (bodyRoot study))]
    current = M.fromList [(hingeVertices h, h) | h <- spreadHinges fixture]
    points = IM.fromList (zip [0 ..] (samples mesh))
    measure (eid, hinge) = do
      preferred <- maybe (Left (SpreadError "missing original crease segment in the body preference model")) Right (M.lookup (hingeVertices hinge) current)
      (angle, _) <- first (SpreadError . explain) (hingeAngle hinge points)
      pure (BodyAngle eid (S.member eid (bodySelected study)) angle (hingeRest hinge) (hingeRest preferred))

-- | Maximum wrapped angle errors relative to the original folded targets,
-- split into selected preferences and retained folds. Neither uses a newly
-- authored spring target as evidence that the original angle was preserved.
bodyAngleErrors :: CraneBody -> MaterialMesh -> Either SpreadError (Double, Double)
bodyAngleErrors study mesh = do
  angles <- bodyAngles study mesh
  let maximumError selected = maximum (0 : [abs (angleError (angleAchieved a) (angleOriginal a)) | a <- angles, angleSelected a == selected])
  pure (maximumError True, maximumError False)

-- | Return strict-original and selective-preference acceptance for the SAME
-- endpoint. Selected preferences have no exact angle gate; all other checks
-- remain required, including solver equilibrium and whole-sheet contact.
bodyAccepted :: CraneBody -> Relaxation -> MaterialMesh -> Either SpreadError (Bool, Bool)
bodyAccepted study result mesh = do
  contact <- spreadCheck fixture mesh
  (selected, retained) <- bodyAngleErrors study mesh
  let accepted = converged result && maxLengthError mesh <= 1e-5 && spreadHeldError fixture mesh == 0 && retained < 1e-5 && contactPassed contact
  pure (accepted && selected < 1e-5, accepted)
  where
    fixture = rootSpread (bodyRoot study)
