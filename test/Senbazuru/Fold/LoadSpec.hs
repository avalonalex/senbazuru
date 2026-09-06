-- |
-- Tests for the library's I/O boundary, both directions.
--
-- Every decision about what FOLD bytes look like is tested on bytes, in
-- "Senbazuru.Fold.TypesSpec", because that is the half with the decisions in
-- it. What is left here is the half that touches the filesystem, and there are
-- only three things worth asserting about it: that a document survives a trip
-- through a real file, that the bytes written are the bytes 'encodeFoldFile'
-- produced, and that a failure arrives as a value rather than as an exception
-- thrown past the caller.
--
-- That last one is why this file exists at all. 'loadFoldFile' and
-- 'saveFoldFile' both promise to turn an 'Control.Exception.IOException' into
-- a 'Left', and only a call that really fails can show that they do.
--
-- The other thing here is 'decodeFile', which chooses a reader from a file
-- name. The choosing is tested on bytes; what the two other readers do with
-- those bytes belongs to "Senbazuru.Import.CpSpec" and
-- "Senbazuru.Import.OpxSpec". The exception is the last group, which is the
-- claim that all three formats of the quarter fold really are the same crease
-- pattern -- a claim about the three readers together that neither of them
-- could make alone.
module Senbazuru.Fold.LoadSpec (spec) where

import Control.Exception (bracket_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Text qualified as T
import Senbazuru.Fold.Load
import Senbazuru.Fold.Types
import Senbazuru.Import.Segments (ImportError (..))
import System.Directory
  ( createDirectoryIfMissing,
    getTemporaryDirectory,
    removeDirectoryRecursive,
  )
import System.FilePath ((</>))
import Test.Hspec

-- | A frame's creases as unordered pairs of endpoints, so that two frames can
-- be compared without their vertex numbering having to agree.
--
-- It cannot: FOLD gives the vertices whatever ids the file listed them under,
-- and a reader rebuilding them from a segment list numbers them in the order
-- the creases first mention them. What the two frames must agree on is the
-- paper, which is what this extracts.
creases :: Frame -> [((Double, Double), (Double, Double), Assignment)]
creases frame =
  sort
    [ (min p q, max p q, assignment)
      | ((VertexId i, VertexId j), assignment) <-
          zip (edgesVertices frame) (edgesAssignment frame),
        p <- at i,
        q <- at j
    ]
  where
    points = [(x, y) | (x : y : _) <- verticesCoords frame]
    -- Total, unlike (!!): an id with no coordinates drops its crease, and the
    -- comparison then fails on a length as loudly as it would on a point.
    at i = take 1 (drop i points)

-- | The same paper turned over top to bottom.
--
-- Every @.cp@ and @.opx@ file measures y downwards, so the quarter fold read
-- from one of them is the quarter fold in @quarter-fold.fold@ mirrored. That
-- is not a discrepancy to paper over -- it is the whole of what
-- 'Senbazuru.Import.Segments.fromScreenPoint' does, and stating it here is how
-- these tests notice if it stops happening.
mirrorY :: Frame -> Frame
mirrorY frame = frame {verticesCoords = map flipRow (verticesCoords frame)}
  where
    flipRow (x : y : rest) = x : negate y : rest
    flipRow row = row

-- | Load a fixture as bytes and decode it by its name.
fixture :: FilePath -> IO (Either LoadError FoldFile)
fixture name = decodeFile name <$> BS.readFile name

quarterFoldCp :: ByteString
quarterFoldCp = "1 0.0 0.0 1.0 0.0\n2 1.0 0.0 0.0 1.0\n"

-- | Run an action with an empty scratch directory, and take it away again.
--
-- Hand-rolled rather than pulled from @temporary@: it is three lines, and a
-- test dependency whose whole job is making one directory is not worth keeping
-- current.
withScratch :: (FilePath -> IO a) -> IO a
withScratch use = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "senbazuru-loadspec"
  bracket_
    (createDirectoryIfMissing True dir)
    (removeDirectoryRecursive dir)
    (use dir)

-- | A document with something in every part of it that reaches the filesystem.
sample :: FoldFile
sample =
  FoldFile
    { fileSpec = Just 1.2,
      fileCreator = Just "senbazuru",
      fileAuthor = Nothing,
      fileTitle = Just "a square",
      fileDescription = Nothing,
      fileClasses = ["singleModel"],
      keyFrame =
        emptyFrame
          { frameClasses = ["creasePattern"],
            verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
            edgesVertices =
              [ (VertexId 0, VertexId 1),
                (VertexId 1, VertexId 2),
                (VertexId 2, VertexId 3),
                (VertexId 3, VertexId 0)
              ],
            edgesAssignment = replicate 4 Border
          },
      otherFrames = []
    }

spec :: Spec
spec = do
  describe "saveFoldFile" $ do
    it "writes a document that loadFoldFile reads back unchanged" $
      withScratch $ \dir -> do
        let path = dir </> "square.fold"
        saveFoldFile path sample `shouldReturn` Right ()
        loaded <- loadFoldFile path
        loaded `shouldBe` Right sample

    it "writes exactly the bytes encodeFoldFile produced" $
      -- The two are meant to be the same thing, one of them with a file
      -- attached. If saveFoldFile ever grows a step of its own -- a trailing
      -- newline, a pretty printer -- every byte-for-byte test in TypesSpec
      -- stops describing what lands on disk.
      withScratch $ \dir -> do
        let path = dir </> "square.fold"
        _ <- saveFoldFile path sample
        written <- BS.readFile path
        written `shouldBe` encodeFoldFile sample

    it "reports a directory that does not exist rather than throwing" $
      withScratch $ \dir -> do
        let path = dir </> "no" </> "such" </> "place.fold"
        result <- saveFoldFile path sample
        case result of
          Right () -> expectationFailure "expected the write to fail"
          Left e -> renderSaveError e `shouldSatisfy` T.isPrefixOf "cannot write "

  describe "decodeFile" $ do
    it "reads a .cp by its extension" $
      fmap (length . edgesVertices . keyFrame) (decodeFile "pattern.cp" quarterFoldCp)
        `shouldBe` Right 2

    it "reads a .CP by its extension too" $
      -- Case-insensitive filesystems hand back whatever case the file was
      -- created with, and nobody typing a path thinks about it.
      decodeFile "PATTERN.CP" quarterFoldCp `shouldBe` decodeFile "pattern.cp" quarterFoldCp

    it "decodes anything else as FOLD, as it did before there was a choice" $ do
      let bytes = encodeFoldFile sample
      decodeFile "square.fold" bytes `shouldBe` Right sample
      decodeFile "square.json" bytes `shouldBe` Right sample
      decodeFile "square" bytes `shouldBe` Right sample

    it "reports a bad line of a .cp rather than a decode failure" $
      -- The reason ImportFailed is its own constructor: aeson has nothing to
      -- say about line 2 of a file it never saw.
      decodeFile "pattern.cp" "1 0.0 0.0 1.0 0.0\n2 1.0 0.0 1.0\n"
        `shouldBe` Left (ImportFailed "pattern.cp" (MalformedLine 2 "expected a type and four coordinates, found 4 fields"))

    it "says which file and which line when it refuses one" $
      case decodeFile "pattern.cp" "0 0.0 0.0 1.0 0.0\n" of
        Left err ->
          renderLoadError err `shouldBe` "cannot read pattern.cp: line 1: unknown line type 0"
        Right _ -> expectationFailure "expected the type code 0 to be refused"

  describe "the quarter fold in all three formats" $ do
    it "is the same crease pattern read from .cp as from .fold" $ do
      fromCp <- fixture "test/fixtures/quarter-fold.cp"
      fromFold <- fixture "test/fixtures/quarter-fold.fold"
      fmap (creases . keyFrame) fromCp
        `shouldBe` fmap (creases . mirrorY . keyFrame) fromFold

    it "is the same crease pattern read from .opx as from .fold" $ do
      fromOpx <- fixture "test/fixtures/quarter-fold.opx"
      fromFold <- fixture "test/fixtures/quarter-fold.fold"
      fmap (creases . keyFrame) fromOpx
        `shouldBe` fmap (creases . mirrorY . keyFrame) fromFold

    it "is twelve creases, so the comparison above is comparing something" $ do
      -- Without this, two readers that both produced nothing would agree.
      fromCp <- fixture "test/fixtures/quarter-fold.cp"
      fmap (length . creases . keyFrame) fromCp `shouldBe` Right 12

    it "loses the faces, which neither of the other two formats records" $ do
      fromCp <- fixture "test/fixtures/quarter-fold.cp"
      fromFold <- fixture "test/fixtures/quarter-fold.fold"
      fmap (length . facesVertices . keyFrame) fromCp `shouldBe` Right 0
      fmap (length . facesVertices . keyFrame) fromFold `shouldBe` Right 4

  describe "loadFoldFile" $ do
    it "reports a file that is not there rather than throwing" $
      withScratch $ \dir -> do
        result <- loadFoldFile (dir </> "absent.fold")
        case result of
          Right _ -> expectationFailure "expected the read to fail"
          Left e -> renderLoadError e `shouldSatisfy` T.isPrefixOf "cannot read "

    it "reads a .cp through loadFile, which loadFoldFile would refuse" $
      withScratch $ \dir -> do
        let path = dir </> "two-creases.cp"
        BS.writeFile path quarterFoldCp
        fromFold <- loadFoldFile path
        fmap (length . edgesVertices . keyFrame) <$> loadFile path
          `shouldReturn` Right 2
        case fromFold of
          Left (DecodeFailed _ _) -> pure ()
          other -> expectationFailure ("expected loadFoldFile to refuse a .cp, got " <> show other)

    it "tells a file it cannot read apart from one that is not FOLD" $
      -- The distinction the two constructors exist for: a path typo and a
      -- corrupt file are different problems for whoever is holding the file.
      withScratch $ \dir -> do
        let path = dir </> "not-fold.fold"
        BS.writeFile path "this is not JSON"
        result <- loadFoldFile path
        case result of
          Right _ -> expectationFailure "expected the decode to fail"
          Left e -> renderLoadError e `shouldSatisfy` T.isPrefixOf "cannot decode "
