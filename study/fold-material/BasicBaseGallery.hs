-- | Reproducible endpoint gallery for the six additional traditional bases.
-- Kept separate from packet relaxation so these small regression fixtures can
-- be regenerated quickly. All drawings use the production SVG backend; only
-- the HTML layout lives here. FOLD downloads retain shared material vertices
-- and explicit layer orders. The optional spread-layer drawings move paper
-- on the page for inspection, not in the exported geometry.
module BasicBaseGallery (writeBasicBases, writeFrogGuide) where

import BasicBases
import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldMaterial
import PanelContact
import Senbazuru.Diagram (Colour (..), Diagram (..), Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Layout (defaultGrid)
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.Rigid (Rigid (..), after, applyRigid, identity, matIdentity, rotationAbout)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking)
import Senbazuru.Render.Camera (View (..), basisFrom, bottomUp, topDown)
import Senbazuru.Render.CreasePattern (creasePatternAuto)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import StudyCase (PoseSpec (..), StudyPose (..), buildPose)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBasicBases :: FilePath -> IO ()
writeBasicBases destination = do
  createDirectoryIfMissing True destination
  entries <- mapM (writeBase destination) basicBases
  template <- TIO.readFile "study/fold-material/basic-bases.html"
  TIO.writeFile (destination </> "basic-bases.html") (T.replace "<!--BASES-->" (T.concat (map fst entries)) template)
  BL.writeFile (destination </> "basic-base-measurements.json") (encode (map snd entries))
  writeFrogGuide destination
  putStrLn ("Wrote six base endpoints, SVG views and basic-bases.html to " ++ destination)

writeBase :: FilePath -> Base -> IO (T.Text, Value)
writeBase destination base = do
  (file, final, measurements) <- checkedBase base
  let source = keyFrame file
      count = length (facesVertices final)
  BL.writeFile (path "cp.fold") (encode file)
  BL.writeFile (path "folded.fold") (encode file {keyFrame = final})
  draw "cp" defaultTheme topDown source
  forM_ [("front", topDown), ("reverse", bottomUp)] $ \(view, basis) -> do
    draw view defaultTheme basis final
    draw (view ++ "-layers") defaultTheme {themeLayerOffset = 4} basis final
  pure (card base count (count * (count - 1) `div` 2), measurements)
  where
    path suffix = destination </> baseId base ++ "-base-" ++ suffix
    draw name theme basis sheet = do
      diagram <- checked (creasePatternAuto theme defaultBudget (View (Just basis) 0) sheet)
      TIO.writeFile (path (name ++ ".svg")) (renderSvg defaultPage {pageWidth = 400, pageHeight = 400, pageMargin = 36} diagram)

checkedBase :: Base -> IO (FoldFile, Frame, Value)
checkedBase base = do
  source <- checked (baseFrame base)
  let file = baseFile base source
  result <- checked (foldFrameWith source)
  orders <- checked (solveStacking (foldedFrame result))
  let final = (foldedFrame result) {faceOrders = orders}
  pose <- checked (buildPose 1 source (PoseSpec "closed endpoint" (edgesFoldAngle source)))
  faces <- checked (frameFaces final)
  alongZ <- forM orders $ \(FaceOrder a b stacking) -> do
    face <- maybe (die "base layer order names a missing face") pure (lookup b [(faceId f, f) | f <- faces])
    let V3 _ _ z = polygonNormal (faceCorners face)
        name = T.pack . show . unFaceId
    unless (abs z > 1e-12 && stacking /= Unordered) (die "base layer order needs an oriented flat face")
    pure (if (stacking == Above) == (z > 0) then (name b, name a) else (name a, name b))
  contact <- checked (checkPanelContact (V3 0 0 1) alongZ [Panel (T.pack (show (unFaceId (faceId f)))) (faceCorners f) | f <- faces])
  let mesh = poseMesh pose
      strain = maximum (0 : map abs (edgeStrains mesh))
      area = areaRatio mesh
  unless (contactPassed contact && componentCount mesh == 1 && strain < 1e-12 && abs (area - 1) < 1e-12) $
    die (baseId base ++ ": endpoint failed material or contact checks")
  pure
    ( file,
      final,
      object
        [ "base" .= baseId base,
          "vertices" .= length (verticesCoords final),
          "panels" .= length faces,
          "maxEdgeStrain" .= strain,
          "areaRatio" .= area,
          "components" .= componentCount mesh,
          "checkedPanelPairs" .= checkedPanelPairs contact,
          "crossingPanels" .= crossingPanels contact,
          "unorderedContacts" .= unorderedContacts contact,
          "reversedOrders" .= reversedOrders contact,
          "uncheckedOrders" .= uncheckedOrders contact,
          "faceOrders" .= orders
        ]
    )

-- | Put the loose corners at the origin and the closed point along +y before
-- using one camera for the whole sequence. The folding engine may hold a
-- different face still after new creases split it. These are rigid turns of
-- the whole packet, including a turnover to expose the petal's working face;
-- they neither reshape the paper nor change face-relative layer orders.
writeFrogGuide :: FilePath -> IO ()
writeFrogGuide destination = do
  entries <- forM frogMilestones $ \(key, base) -> do
    (file, final, report) <- checkedBase base
    positions <- checked (frameVertices final)
    let material = zip (verticesCoords (keyFrame file)) positions
        point xy = maybe (die "frog guide is missing a material landmark") pure (lookup xy material)
    origin <- point [0, 0]
    closed <- point [0.5, 0.5]
    let V3 dx dy _ = closed ^-^ origin
        zero = V3 0 0 0
        upright = rotationAbout zero (V3 0 0 1) (pi / 2 - atan2 dy dx)
        turnover = if key `elem` ["square", "one-squash"] then identity else rotationAbout zero (V3 0 1 0) pi
        placement = turnover `after` upright `after` Rigid matIdentity (zero ^-^ origin)
        coords p = let V3 x y z = applyRigid placement p in [x, y, z]
        presented = final {verticesCoords = map coords positions}
    drawing <- checked (creasePatternAuto defaultTheme defaultBudget (View (Just topDown) 0) presented)
    let labels = [Label (Colour "#756956") 12 (V2 0 0.77) "Closed point", Label (Colour "#756956") 12 (V2 0 (-0.06)) "Four loose corners"]
        aligned = diagramWithExtent (Box (V2 (-0.4) (-0.09)) (V2 0.4 0.82)) (diagramShapes drawing ++ labels)
        path suffix = destination </> "frog-guide-" ++ key ++ suffix
    TIO.writeFile (path ".svg") (renderSvg defaultPage {pageWidth = 380, pageHeight = 420, pageMargin = 20} aligned)
    BL.writeFile (path ".fold") (encode file {keyFrame = presented})
    pure (file {keyFrame = presented}, report)
  case entries of
    [] -> die "frog guide has no milestones"
    (first, _) : _ -> do
      let sequenceFile = first {fileTitle = Just "Frog base folding checkpoints", fileClasses = ["diagrams"], keyFrame = emptyFrame, otherFrames = map (keyFrame . fst) entries}
      BL.writeFile (destination </> "frog-base-sequence.fold") (encode sequenceFile)
      above <- sideView (-1)
      below <- sideView 1
      forM_ [("side-above", above), ("side-below", below), ("front", topDown)] $ \(name, basis) -> do
        page <- checked (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) (View (Just basis) 0) False (otherFrames sequenceFile))
        drawing <- maybe (die "frog sequence has no figures") pure page
        TIO.writeFile (destination </> "frog-sequence-" ++ name ++ ".svg") (renderSvg defaultPage {pageWidth = 1000, pageHeight = 720} drawing)
  BL.writeFile (destination </> "frog-guide-measurements.json") (encode (map snd entries))
  TIO.readFile "study/fold-material/frog-instructions.html" >>= TIO.writeFile (destination </> "frog-instructions.html")
  where
    -- Equal horizontal and vertical components look across the paper at 45
    -- degrees. Keep its closed point up the page, as in the straight-on guide.
    sideView z = maybe (die "frog sequence side camera is invalid") pure (basisFrom (V3 (-1) 0 z) (V3 0 1 0))

card :: Base -> Int -> Int -> T.Text
card base panels pairs =
  let key = T.pack (baseId base)
      title = escapeXml (baseTitle base)
      prefix = key <> "-base-"
      side = if baseId base `elem` ["helmet", "diamond"] then "reverse" else "front"
      caption = "Closed endpoint · " <> side <> " view"
      link suffix label = "<a" <> (if label == "SVG" then " class=\"svg-download\"" else "") <> " href=\"" <> prefix <> suffix <> "\" download>" <> label <> "</a>"
   in "<article id=\""
        <> key
        <> "\"><header><h2>"
        <> title
        <> "</h2><span>"
        <> T.pack (show panels)
        <> " panels · "
        <> T.pack (show pairs)
        <> " contact pairs</span></header>"
        <> "<p>"
        <> escapeXml (baseDescription base)
        <> "</p><div class=\"figures\">"
        <> "<figure><img src=\""
        <> prefix
        <> "cp.svg\" alt=\""
        <> title
        <> " crease pattern\"><figcaption>Crease pattern</figcaption></figure>"
        <> "<figure><img class=\"endpoint\" data-base=\""
        <> key
        <> "\" data-flap-side=\""
        <> side
        <> "\" src=\""
        <> prefix
        <> side
        <> ".svg\" alt=\""
        <> title
        <> " · "
        <> caption
        <> "\"><figcaption class=\"view-label\">"
        <> caption
        <> "</figcaption></figure></div>"
        <> "<footer>"
        <> link "cp.fold" "Crease FOLD"
        <> link "folded.fold" "Folded FOLD"
        <> link (side <> ".svg") "SVG"
        <> (if baseId base == "frog" then "<a class=\"guide\" href=\"frog-instructions.html\">Folding instructions</a>" else "")
        <> "<span>Material + contact checks passed</span></footer></article>"

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
