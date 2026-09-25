-- | Find compatible near-closed crease angles before making a flexible mesh.
-- Each panel moves rigidly, so it cannot stretch. A walk through the panels
-- gives provisional placements, but a loop around a crease intersection may
-- not join up. We minimize disagreement in both position AND orientation on
-- every connection; testing shared endpoints alone can miss a wrong angle.
-- See docs/notes/folding-by-transforms.md and docs/glossary.md.
--
-- This small study needs provisional transforms while angles are incompatible;
-- Folding deliberately refuses those. The walk here is only an objective for
-- the angle search. 'foldFrameWith' remains the independent final authority.
-- A successful closure says nothing about contact, equilibrium or a route.
module CreaseSeed
  ( CreaseSeedError (..),
    AngleStep (..),
    AngleSeed (..),
    coordinateCreases,
    creaseResiduals,
    creasePlacements,
  )
where

import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', sortOn)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Query (edgeKey, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.Rigid
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import SparseSolve qualified as Sparse

newtype CreaseSeedError = CreaseSeedError Text deriving stock (Eq, Show)

instance Explain CreaseSeedError where explain (CreaseSeedError message) = message

data AngleStep = AngleStep
  { angleStepDegrees :: [Double],
    angleStepResidual :: Double,
    angleStepCost :: Double,
    angleStepFraction :: Maybe Double,
    angleLinearResidual :: Maybe Double
  }
  deriving stock (Eq, Show)

data AngleSeed = AngleSeed
  { angleFrame :: Frame,
    angleHistory :: [AngleStep],
    angleStop :: Text,
    angleClosed :: Bool,
    angleAnchor :: EdgeId
  }
  deriving stock (Eq, Show)

-- The axis follows the counterclockwise boundary of the first face.
data Link = Link Int Int Int VertexId VertexId

data Problem = Problem Frame (IM.IntMap V3) [Link] (IM.IntMap Double)

prepare :: Frame -> Either CreaseSeedError Problem
prepare source = do
  sheet <- first (CreaseSeedError . explain) (withPlanarFaces source)
  points <- first (CreaseSeedError . explain) (frameVertices sheet)
  unless (not (null points) && all (\(V3 x y z) -> all finite [x, y, z] && abs z < 1e-12) points) (bad "crease initialization needs a finite planar pattern at z=0")
  let ps = IM.fromList (zip [0 ..] points)
      point (VertexId i) = lookupPoint ps i
      orient ring = do
        corners <- traverse point ring
        let V3 _ _ nz = polygonNormal corners
        unless (abs nz > 1e-14) (bad "crease initialization needs nondegenerate faces")
        pure (if nz > 0 then ring else reverse ring)
  rings <- traverse orient (facesVertices sheet)
  when (null rings) (bad "crease initialization needs faces")
  let incidence = M.fromListWith (++) [(edgeKey u v, [(i, u, v)]) | (i, ring) <- zip [0 ..] rings, (u, v) <- ringEdges ring]
      edges = zip3 [0 ..] (edgesVertices sheet) (edgesAssignment sheet)
  unless (length edges == length (edgesVertices sheet)) (bad "crease initialization needs an assignment for every edge")
  links <-
    concat
      <$> traverse
        ( \(eid, (u, v), _) -> case sortOn (\(i, _, _) -> i) (M.findWithDefault [] (edgeKey u v) incidence) of
            [(_, _, _)] -> pure []
            [(a, p, q), (b, _, _)] -> pure [Link a b eid p q]
            _ -> bad "crease initialization needs one or two owners per edge"
        )
        edges
  let internal = [i | Link _ _ i _ _ <- links]
      signs = IM.fromList [(i, if a == Mountain then -1 else 1) | (i, _, a) <- edges, i `elem` internal, a `elem` [Mountain, Valley]]
  when (IM.null signs) (bad "crease initialization needs an internal mountain or valley")
  pure (Problem sheet {facesVertices = rings, frameClasses = ["creasePattern"], frameAttributes = ["2D"], faceOrders = [], frameExtras = mempty} ps links signs)

-- Exported for independent derivative/closure controls, not unchecked poses.
creaseResiduals :: Frame -> [Double] -> Either CreaseSeedError [Double]
creaseResiduals source degrees = do
  problem@(Problem sheet _ _ _) <- prepare source
  unless (length degrees == length (edgesVertices sheet) && all finite degrees) (bad "one finite angle is required per edge")
  residuals problem (IM.fromList (zip [0 ..] (map radians degrees)))

-- | Provisional panel placements for construction constraints only. Loops may
-- disagree; callers must never weld them into an apparently connected sheet.
creasePlacements :: Frame -> [Double] -> Either CreaseSeedError (IM.IntMap Rigid)
creasePlacements source degrees = do
  problem@(Problem sheet _ _ _) <- prepare source
  unless (length degrees == length (edgesVertices sheet) && all finite degrees) (bad "one finite angle is required per edge")
  placePanels problem (IM.fromList (zip [0 ..] (map radians degrees)))

linkRotation :: IM.IntMap V3 -> IM.IntMap Double -> Int -> VertexId -> VertexId -> Either CreaseSeedError Rigid
linkRotation points angles eid u v = do
  p <- lookupPoint points (unVertexId u)
  q <- lookupPoint points (unVertexId v)
  pure (rotationAbout p (q ^-^ p) (negate (IM.findWithDefault 0 eid angles)))

placePanels :: Problem -> IM.IntMap Double -> Either CreaseSeedError (IM.IntMap Rigid)
placePanels (Problem sheet points links _) angles = do
  placements <- walk (IM.singleton 0 identity) [0]
  unless (IM.size placements == length (facesVertices sheet)) (bad "crease initialization has disconnected panels")
  pure placements
  where
    neighbours i = [(b, e, u, v) | Link a b e u v <- links, a == i] ++ [(a, e, v, u) | Link a b e u v <- links, b == i]
    walk placed [] = pure placed
    walk placed (i : queue) = do
      parent <- maybe (bad "missing provisional parent") Right (IM.lookup i placed)
      (next, more) <- foldl' (add parent) (Right (placed, [])) (neighbours i)
      walk next (queue ++ more)
    add parent acc (j, e, u, v) = do
      (placed, queue) <- acc
      if IM.member j placed
        then pure (placed, queue)
        else do
          turn <- linkRotation points angles e u v
          pure (IM.insert j (parent `after` turn) placed, queue ++ [j])

residuals :: Problem -> IM.IntMap Double -> Either CreaseSeedError [Double]
residuals problem@(Problem _ points links _) angles = do
  placements <- placePanels problem angles
  concat <$> traverse (difference placements) links
  where
    difference placed (Link a b e u v) = do
      pa <- maybe (bad "missing provisional face") Right (IM.lookup a placed)
      pb <- maybe (bad "missing provisional face") Right (IM.lookup b placed)
      turn <- linkRotation points angles e u v
      let predicted = pa `after` turn
          orient axis = matApply (rigidLinear pb) axis ^-^ matApply (rigidLinear predicted) axis
      pure (concatMap coords (rigidOffset pb ^-^ rigidOffset predicted : map orient [V3 1 0 0, V3 0 1 0, V3 0 0 1]))

-- | One prescribed family: signed 175 degrees, first physical crease fixed,
-- other magnitudes 150..179.99 degrees. No adaptive restarts or alternative
-- seeds. Numerical angle corrections are not samples of a folding motion.
coordinateCreases :: Int -> Frame -> Either CreaseSeedError AngleSeed
coordinateCreases budget source = do
  unless (budget >= 0 && budget <= 40) (bad "angle initialization budget must be between zero and forty")
  problem@(Problem sheet _ _ signs) <- prepare source
  anchor <- maybe (bad "missing angle anchor") (pure . fst) (IM.lookupMin signs)
  let start = IM.map (radians 175 *) signs
      free = filter (/= anchor) (IM.keys signs)
      values angles = [IM.findWithDefault 0 i angles * 180 / pi | i <- [0 .. length (edgesVertices sheet) - 1]]
      record angles rs = AngleStep (values angles) (largest rs) (cost rs)
      finish angles history reason closed = AngleSeed sheet {edgesFoldAngle = values angles} (reverse history) reason closed (EdgeId anchor)
      valid angles = all (\(i, s) -> let v = s * IM.findWithDefault 0 i angles in finite v && v >= radians 150 && v <= radians 179.99) (IM.toList signs)
      go n angles history = do
        rs <- residuals problem angles
        if largest rs <= 1e-10
          then pure (finish angles history "closed" True)
          else
            if n >= budget
              then pure (finish angles history "correction-budget" False)
              else do
                columns <-
                  traverse
                    ( \i -> do
                        plus <- residuals problem (IM.adjust (+ 1e-6) i angles)
                        minus <- residuals problem (IM.adjust (subtract 1e-6) i angles)
                        pure (i, zipWith (\a b -> (a - b) / 2e-6) plus minus)
                    )
                    free
                -- Columns say how each closure residual changes with one angle.
                -- Assemble the damped least-squares direction, then verify its
                -- original equations rather than trusting the factor alone.
                let rows = foldl' (\acc (i, column) -> zipWith (IM.insert i) column acc) (replicate (length rs) IM.empty) columns
                    rhs = foldl' (IM.unionWith (+)) (IM.fromList [(i, 0) | i <- free]) (zipWith (\r row -> IM.map (negate r *) row) rs rows)
                case Sparse.factorNormal 1e-8 free rows of
                  Nothing -> pure (finish angles history "linear-factor-failure" False)
                  Just factor -> do
                    let delta = Sparse.applyFactor factor rhs
                        productRow row = sum (IM.elems (IM.intersectionWith (*) row delta))
                        action = foldl' (IM.unionWith (+)) (IM.map (1e-8 *) delta) [IM.map (productRow row *) row | row <- rows]
                        linear = largest (IM.elems (IM.unionWith (-) action rhs))
                        magnitude = largest (IM.elems delta)
                        scale = if magnitude > radians 5 then radians 5 / magnitude else 1
                        search [] = pure Nothing
                        search (fraction : rest) = do
                          let candidate = IM.unionWith (+) angles (IM.map (fraction * scale *) delta)
                          if not (valid candidate)
                            then search rest
                            else do
                              afterRows <- residuals problem candidate
                              if all finite afterRows && cost afterRows < cost rs
                                then pure (Just (candidate, record candidate afterRows (Just fraction) (Just linear)))
                                else search rest
                    if not (all finite delta && finite linear) || linear > 1e-10 * max 1 (largest (IM.elems rhs))
                      then pure (finish angles history "linear-residual-failure" False)
                      else
                        search [2 ** negate (fromIntegral i) | i <- [0 :: Int .. 12]] >>= \case
                          Nothing -> pure (finish angles history "line-search-budget" False)
                          Just (next, step) -> go (n + 1) next (step : history)
  rs <- residuals problem start
  go 0 start [record start rs Nothing Nothing]

lookupPoint :: IM.IntMap V3 -> Int -> Either CreaseSeedError V3
lookupPoint ps i = maybe (bad "missing material point") Right (IM.lookup i ps)

bad :: Text -> Either CreaseSeedError a
bad = Left . CreaseSeedError

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

radians :: Double -> Double
radians d = d * pi / 180

largest :: [Double] -> Double
largest = maximum . (0 :) . map abs

cost :: [Double] -> Double
cost = sum . map (\x -> x * x / 2)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
