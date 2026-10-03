-- | Choose, and check, the angle at which a released control holds the
-- crane wing's base.
--
-- Above the wing's widest point the paper between it and the hinge is four
-- layers deep, and a released control that let it bend as a sheet stalled
-- (#455). So 'rigidBase' turns that base as one piece about the hinge, at an
-- angle the control has to be given. A *released* control is one that leaves
-- the paper at the hinge free to bend instead of holding it; see the glossary
-- for controls. Two owner decisions say which angle:
--
-- * Decision 35: the angle of least bending energy, which 'searchBase' finds
--   by golden-section search, sixteen solves.
-- * Decision 36: in a gallery that runs that search on its flat-preference
--   control, every other released control takes the angle found there, and
--   'checkBase' solves it again 1° either side. On the body-free control at
--   the root, that control's own search chose the same angle at 23 times
--   the cost of one solve.
--
-- The thing a newcomer would get wrong: a solve here must be the gallery's
-- own. crane-internal drops contact forces in some controls, and a search
-- or check that solved with another solver would compare the energies of a
-- different problem. So both take the solve as a function ('Solve').
module RigidBase
  ( Solve,
    spreadSolve,
    BaseSearch (..),
    searchBase,
    goldenSection,
    BaseCheck (..),
    checkBase,
    checkPassed,
    sidesPass,
    Base (..),
    baseReport,
  )
where

import Control.Monad (forM)
import CraneRoot
import CraneSpread
import Data.Aeson (Value, object, (.=))
import Data.Bifunctor (first)
import Data.Text (Text)
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (explain)
import Senbazuru.Origami.Surface
import WingBending (finalMesh)

-- | How a gallery solves one control, given the control with its base
-- already turned: the solver's result, and whatever else the gallery
-- reports about the solve, such as crane-internal's refused corrections.
type Solve a = CraneRoot -> Either SpreadError (Relaxation, a)

-- | The ordinary solve, with every retained contact force, for a gallery
-- that reports nothing else about it.
spreadSolve :: Settings -> Solve ()
spreadSolve settings root = (,()) <$> solveSpread settings (rootSpread root)

-- | A released control whose base turns as one piece ('rigidBase'), held at
-- the angle that leaves the paper, hinge included, the least bending energy.
data BaseSearch a = BaseSearch
  { baseDegrees :: !Double,
    baseStudy :: !CraneRoot,
    baseResult :: !Relaxation,
    baseExtra :: a,
    baseMesh :: !MaterialMesh,
    -- | Every angle tried, in degrees, with its bending energy and whether
    -- its solve converged, in order. An unconverged energy still steers the
    -- search, so the record says which ones were.
    baseTried :: ![(Double, Double, Bool)]
  }

-- | Search 15 to 45 degrees, to 0.05 degree. The first two solves start
-- from the control's own mesh, and each later one from the mesh of the
-- bracket point beside it.
searchBase :: Solve a -> CraneRoot -> Either SpreadError (BaseSearch a)
searchBase solve study = do
  ((theta, _, (_, found)), tried) <- goldenSection 0.05 15 45 (spreadMesh (rootSpread study), Nothing) solveAt
  (turned, result, extra, mesh) <- maybe (Left (SpreadError "the base search made no solve")) Right found
  let record = [(degree, energy, maybe False (\(_, r, _, _) -> converged r) made) | (degree, energy, (_, made)) <- tried]
  -- Force the record now. Each element is otherwise a thunk over its solve's
  -- mesh, history and audit, and a gallery that keeps the search for its
  -- whole run would keep all sixteen solves with it.
  mapM_ (\(degree, energy, settled) -> degree `seq` energy `seq` settled `seq` Right ()) record
  pure (BaseSearch theta turned result extra mesh record)
  where
    solveAt (start, _) theta = do
      (turned, result, extra, mesh, energy) <- solveTurned solve study start theta
      pure (energy, (mesh, Just (turned, result, extra, mesh)))

-- | A released control held at an angle another control's search found
-- (owner decision 36), and the two solves 1° either side that check it.
data BaseCheck a = BaseCheck
  { checkDegrees :: !Double,
    checkStudy :: !CraneRoot,
    checkResult :: !Relaxation,
    checkExtra :: a,
    checkMesh :: !MaterialMesh,
    checkEnergy :: !Double,
    -- | Each side, in degrees, with its bending energy and whether its solve
    -- converged. An unconverged side is compared all the same, as the search
    -- compares its own, and the record says so.
    checkSides :: ![(Double, Double, Bool)]
  }

-- | Solve the control at @theta@ from its own mesh, then 1° either side,
-- each side starting from the endpoint at @theta@, the nearest solve, as
-- the search's later solves start from their nearest.
checkBase :: Solve a -> Double -> CraneRoot -> Either SpreadError (BaseCheck a)
checkBase solve theta study = do
  (turned, result, extra, mesh, energy) <- solveTurned solve study (spreadMesh (rootSpread study)) theta
  sides <- forM [theta - 1, theta + 1] $ \side -> do
    (_, sideResult, _, _, sideEnergy) <- solveTurned solve study mesh side
    -- Forced here, so that a side keeps nothing of its solve but these.
    let !settled = converged sideResult
        !energy' = sideEnergy
    pure (side, energy', settled)
  pure (BaseCheck theta turned result extra mesh energy sides)

-- | The check fails, and the control is refused, when either side ends with
-- less bending energy than the angle it checks.
checkPassed :: BaseCheck a -> Bool
checkPassed check = sidesPass (checkEnergy check) (checkSides check)

-- | Whether every side, in degrees with its energy and convergence, ends with
-- at least @energy@. A side that ends equal passes, and an unconverged side
-- counts like any other.
sidesPass :: Double -> [(Double, Double, Bool)] -> Bool
sidesPass energy = all (\(_, side, _) -> side >= energy)

-- | How a trial's base angle was set: by its own search, by another
-- control's search and checked 1° either side, or taken without the check
-- by a trial that makes no choice of its own, such as a continuation or a
-- control made to fail (owner decision 36).
data Base a = Searched | Checked !(BaseCheck a) | Taken

-- | How the trial's base angle was set, with the evidence for it.
baseReport :: BaseSearch a -> Base a -> Value
baseReport search = \case
  Searched -> object ["set" .= ("searched" :: Text), "tried" .= [angle d e c | (d, e, c) <- baseTried search]]
  Checked check -> object ["set" .= ("checked" :: Text), "energy" .= checkEnergy check, "passed" .= checkPassed check, "sides" .= [angle d e c | (d, e, c) <- checkSides check]]
  Taken -> object ["set" .= ("taken" :: Text)]
  where
    angle :: Double -> Double -> Bool -> Value
    angle degrees energy settledThere = object ["degrees" .= degrees, "energy" .= energy, "converged" .= settledThere]

-- | Turn the control's base to @degrees@, starting from @start@, solve it,
-- and measure the bending energy of the paper, hinge included.
solveTurned :: Solve a -> CraneRoot -> MaterialMesh -> Double -> Either SpreadError (CraneRoot, Relaxation, a, MaterialMesh, Double)
solveTurned solve study start degrees = do
  let turned = rigidBase degrees study start
  (result, extra) <- solve turned
  mesh <- first (SpreadError . explain) (finalMesh result)
  (crease, panel) <- first (SpreadError . explain) (bendingEnergy (spreadHinges (rootSpread turned)) mesh)
  pure (turned, result, extra, mesh, crease + panel)

-- | The least value of @f@ on [@lo@, @hi@] by golden-section search, narrowed
-- until the bracket is narrower than @tolerance@, which must be positive and
-- well above the rounding of @lo@ and @hi@: a bracket that rounding stops
-- shrinking never gets narrower, and the search would not end. Each
-- evaluation is handed the payload of the interior point that stays beside
-- it, the nearest point already evaluated, so a solve can start from the last
-- one nearby. Returns the best argument, its value and
-- payload, and every evaluation, with its payload, in the order made. It
-- assumes one minimum in the bracket, as a search by bracketing must.
goldenSection :: Double -> Double -> Double -> s -> (s -> Double -> Either e (Double, s)) -> Either e ((Double, Double, s), [(Double, Double, s)])
goldenSection tolerance lo hi start f = do
  (fc, sc) <- f start c0
  (fd, sd) <- f start d0
  go lo hi (c0, fc, sc) (d0, fd, sd) [(d0, fd, sd), (c0, fc, sc)]
  where
    phi = (sqrt 5 - 1) / 2
    c0 = hi - phi * (hi - lo)
    d0 = lo + phi * (hi - lo)
    go a b c@(xc, fc, sc) d@(xd, fd, sd) tried
      | b - a < tolerance = Right (if fc <= fd then c else d, reverse tried)
      | fc <= fd = do
          let x = xd - phi * (xd - a)
          (fx, sx) <- f sc x
          go a xd (x, fx, sx) c ((x, fx, sx) : tried)
      | otherwise = do
          let x = xc + phi * (b - xc)
          (fx, sx) <- f sd x
          go xc b d (x, fx, sx) ((x, fx, sx) : tried)
