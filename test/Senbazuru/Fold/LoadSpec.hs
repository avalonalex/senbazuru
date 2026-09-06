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
module Senbazuru.Fold.LoadSpec (spec) where

import Control.Exception (bracket_)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Senbazuru.Fold.Load
import Senbazuru.Fold.Types
import System.Directory
  ( createDirectoryIfMissing,
    getTemporaryDirectory,
    removeDirectoryRecursive,
  )
import System.FilePath ((</>))
import Test.Hspec

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

  describe "loadFoldFile" $ do
    it "reports a file that is not there rather than throwing" $
      withScratch $ \dir -> do
        result <- loadFoldFile (dir </> "absent.fold")
        case result of
          Right _ -> expectationFailure "expected the read to fail"
          Left e -> renderLoadError e `shouldSatisfy` T.isPrefixOf "cannot read "

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
