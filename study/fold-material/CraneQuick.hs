-- | The quick tier for the crane with a wing spread (#474): a settled shape in
-- a minute or two, where the research galleries take hours.
--
-- It is the flat-preference control at the wing's root, which holds the
-- crane's body still while the wing spreads. The wing's base, four layers deep
-- above its widest point, turns as one piece ('rigidBase') at the angle
-- 'searchNear' finds: within 5° of the turn the control's root starts at,
-- widening to the full 15-45° search only if the least energy lands at an end
-- of that bracket. A full search spends most of its time on far angles that
-- never settle; the narrow one skips them.
--
-- Holding the body is the owner's choice for a quick tier (decision 39), and
-- the output says so: its GLB's fidelity record is a settled geometry that
-- names the body and the turned base as held, so it claims a true solve of
-- held paper and no more. At the root a held solve and a released one differ
-- by 0.0003 px at 600 px per sheet unit, for 7.5 CPU seconds against 1,046
-- (#474).
--
-- Given the FOLD endpoints of the research galleries' released controls, it
-- also measures how far its own endpoint lies from each, in pixels at the
-- scale it draws at: the comparison decision 39 keeps, and #474's check. Only
-- an endpoint its gallery accepted means anything here, and a FOLD cannot say
-- whether it was: a diagnostic one compares just as readily.
module CraneQuick (writeCraneQuick) where

import Control.Exception (evaluate)
import Control.Monad (forM, forM_, unless)
import CraneRoot
import CraneSpread
import CraneSpreadGallery (screenKeys, spreadFigure)
import CraneWing (wingRoot)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation
import Numeric (showFFloat)
import RigidBase (BaseSearch (..), searchNear, spreadSolve, startingTurn)
import ScreenReport (Figure (..), PageScale (..), thresholdsJson)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Fidelity (Geometry (..))
import Senbazuru.Render.Gltf (ExportMode (..), GlbOptions (..), plainGlb, renderSurfaceGlbWith)
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

-- | Solve the quick tier into @destination@ @/crane-quick@, and compare it
-- with each FOLD endpoint in @references@: accepted ones, on its mesh.
writeCraneQuick :: FilePath -> [FilePath] -> IO ()
writeCraneQuick destination references = do
  let output = destination </> "crane-quick"
      title = "Quick tier · body held, wing spread from its root" :: Text
  createDirectoryIfMissing True output
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  -- The wing hinges at its root, found by rule (owner decisions 34 and 35).
  hinge <- either (die . T.unpack) pure (wingRoot source)
  study <- checked (craneRootAt hinge source 3 FlatRoot)
  centre <- checked (startingTurn study)
  putStrLn ("Searching the base angle within 5 degrees of " ++ showFFloat (Just 3) centre "")
  hFlush stdout
  start <- getCPUTime
  (found, widened) <- checked (searchNear (spreadSolve (Settings 40 1e-5)) centre study)
  _ <- evaluate (baseDegrees found)
  settled <- getCPUTime
  let root = baseStudy found
      fixture = rootSpread root
      mesh = baseMesh found
      result = baseResult found
      theta = baseDegrees found
      held = ["the body", "the wing's base, turned as one piece at " <> T.pack (showFFloat (Just 3) theta "°")]
  accepted <- checked (rootAccepted root result mesh)
  contact <- checked (spreadCheck fixture mesh)
  sheet <- checked (spreadSurface fixture mesh)
  let drawing = spreadFigure [sheet]
      own = if accepted then either (const Nothing) Just drawing else Nothing
  (_, screened) <- either (die . T.unpack) pure (screenKeys fixture contact (isJust own) mesh)
  -- The solve's own outputs go first: it took minutes, and a reference that
  -- will not compare must not cost them. The GLB, which can be refused, goes
  -- last.
  BL.writeFile (output </> "quick.fold") (encode (FoldFile (Just 1.2) (Just "senbazuru quick tier") Nothing (Just title) Nothing [] (materialFrame sheet) []))
  forM_ own $ \figure' -> TIO.writeFile (output </> "quick.svg") (figureSvg figure')
  let measured =
        [ "hingeY" .= hinge,
          "startingTurnDegrees" .= centre,
          "baseDegrees" .= theta,
          "widenedToFullSearch" .= widened,
          "tried" .= [object ["degrees" .= d, "energy" .= e, "converged" .= c] | (d, e, c) <- baseTried found],
          "held" .= held,
          "accepted" .= accepted,
          "converged" .= converged result,
          "maxRelativeEdgeError" .= maxLengthError mesh,
          "heldPositionError" .= spreadHeldError fixture mesh,
          "contact" .= contact,
          "triangles" .= length (triangles mesh),
          "solveCpuSeconds" .= (fromIntegral (settled - start) / 1e12 :: Double)
        ]
          ++ maybe [] (\figure' -> ("screenThresholds" .= thresholdsJson (figureScale figure')) : screened (figureScale figure')) own
  comparisons <- forM references (compareWith (figureScale <$> own) sheet)
  BL.writeFile (output </> "checks.json") (encode (object (measured ++ ["comparisons" .= comparisons])))
  -- The record names what was held (owner decision 39). The stable view can
  -- be refused, as a solved body's can be; the complete scene still carries
  -- the record.
  let glb mode = renderSurfaceGlbWith (plainGlb mode) {glbGeometry = Just (Settled held)} defaultBudget (Just title) sheet
  case glb VisiblePaper of
    Right bytes -> BS.writeFile (output </> "quick.glb") bytes
    Left err -> do
      putStrLn ("Stable view refused: " ++ T.unpack (explain err))
      bytes <- checked (glb CompletePaper)
      BS.writeFile (output </> "quick-complete.glb") bytes
  unless accepted (putStrLn "The quick tier's solve is not accepted; it is written as a diagnostic")
  putStrLn ("Quick tier: base " ++ showFFloat (Just 3) theta "" ++ " degrees" ++ (if widened then " after widening to the full search" else "") ++ ", accepted " ++ show accepted ++ ", solve CPU s " ++ show (fromIntegral (settled - start) / 1e12 :: Double))

-- | How far the quick endpoint lies from a reference endpoint on the same
-- mesh: the largest distance between matching vertices, in sheet units and in
-- pixels at the quick tier's drawing scale and at the screen's 600. A
-- reference that cannot be read, or lies on another mesh, is recorded as not
-- compared rather than ending the run: by then the solve has taken minutes.
compareWith :: Maybe PageScale -> Surface V2 -> FilePath -> IO Value
compareWith scale sheet path = do
  loaded <- loadFoldFile path
  let notOnMesh :: Either Text a
      notOnMesh = Left "it is not on the quick tier's mesh, so its vertices cannot be compared"
      compared = do
        file <- first explain loaded
        reference <- first explain (surfaceFromFrame (keyFrame file) >>= requireMaterialCoordinates)
        unless (facesVertices (surfaceFrame reference) == facesVertices (surfaceFrame sheet)) notOnMesh
        maybe notOnMesh Right (largestDisplacement (surfaceSamples sheet) (surfaceSamples reference))
  case compared of
    Left err -> do
      putStrLn (path ++ ": not compared: " ++ T.unpack err)
      pure (object ["reference" .= path, "error" .= err])
    Right largest -> do
      putStrLn (path ++ ": largest displacement " ++ show largest ++ " sheet units, " ++ maybe "no drawing scale" (\s -> show (pixelsPerSheet s * largest) ++ " px at this tier's scale") scale ++ ", " ++ show (600 * largest) ++ " px at 600")
      pure (object ["reference" .= path, "largestDisplacement" .= largest, "pixelsAtThisScale" .= fmap ((* largest) . pixelsPerSheet) scale, "pixelsAt600" .= (600 * largest)])

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
