-- | Generate recorded equilibrium attempts, never interpolated folding motion.
-- Geometry and measurements are computed here; the HTML only selects and views
-- the saved meshes. The unit-square packet assumptions live in FoldContact.
module BendingGallery (writeBendingStudy) where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Maybe (catMaybes)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldContact
import FoldMaterial
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3 (..))
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBendingStudy :: FilePath -> IO ()
writeBendingStudy destination = do
  createDirectoryIfMissing True destination
  runs <-
    mapM
      generate
      [ ("Single fold", Single, defaultBending {firstRestAngle = 150 * pi / 180}),
        ("Double fold · softer panels", Double, defaultBending {panelStiffness = 0.2}),
        ("Double fold · stiffer panels", Double, defaultBending)
      ]
  let document = encode (object ["runs" .= runs, "lengthTolerance" .= lengthTolerance settings, "contactTolerance" .= contactTolerance])
  BL.writeFile (destination </> "bending.json") document
  template <- TIO.readFile "study/fold-material/bending.html"
  TIO.writeFile (destination </> "bending.html") (T.replace "/*BENDING_DATA*/null" (TE.decodeUtf8 (BL.toStrict document)) template)
  putStrLn ("Wrote bending.html and bending.json to " ++ destination)
  where
    settings = Settings 100 1e-5
    generate (title, which, bending) = do
      let mesh = sharpMesh 4 which
      hinges <- checked (buildHinges bending which mesh)
      result <- checked (relaxBending settings bending which mesh)
      states <- mapM (snapshot hinges which) (checkpoints result)
      putStrLn ((title :: String) ++ ": equilibrium checks " ++ show (converged result))
      pure (object ["title" .= title, "converged" .= converged result, "firstTarget" .= degrees (firstRestAngle bending), "secondTarget" .= degrees (secondRestAngle bending), "panelStiffness" .= panelStiffness bending, "creaseStiffness" .= creaseStiffness bending, "states" .= states])

snapshot :: [Hinge] -> FoldCase -> Checkpoint -> IO Value
snapshot hinges which checkpoint = do
  let mesh = checkpointMesh checkpoint
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      contacts = packetCheck which mesh
      coords (V3 x y z) = [x, y, z]
      triple (a, b, c) = [a, b, c]
      measured = [principalStrains t | t <- resolvedTriangles mesh]
      strains = catMaybes measured
  (crease, panel) <- checked (bendingEnergy hinges mesh)
  let angleValue hinge = do
        (angle, _) <- checked (hingeAngle hinge vertices)
        let (a, b, c, d) = hingeVertices hinge
        pure (object ["vertices" .= [a, b, c, d], "role" .= show (hingeRole hinge), "angle" .= degrees angle, "rest" .= degrees (hingeRest hinge)])
  angles <- mapM angleValue hinges
  pure
    ( object
        [ "iteration" .= completedIterations checkpoint,
          "positions" .= map (coords . position) (samples mesh),
          "material" .= map (\s -> [materialU s, materialV s]) (samples mesh),
          "triangles" .= map triple (triangles mesh),
          "panels" .= [packetLayer which ((materialU a + materialU b + materialU c) / 3) ((materialV a + materialV b + materialV c) / 3) | (a, b, c) <- resolvedTriangles mesh],
          "angles" .= angles,
          "creaseEnergy" .= crease,
          "panelEnergy" .= panel,
          "lengthError" .= checkpointError checkpoint,
          "minPrincipalStrain" .= minimum (0 : map fst strains),
          "maxPrincipalStrain" .= maximum (0 : map snd strains),
          "components" .= componentCount mesh,
          "areaRatio" .= areaRatio mesh,
          "maxOrderViolation" .= maxOrderViolation contacts,
          "violatingPairs" .= violatingPairs contacts,
          "uncheckedTriangles" .= uncheckedTriangles contacts
        ]
    )

degrees :: Double -> Double
degrees angle = angle * 180 / pi

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
