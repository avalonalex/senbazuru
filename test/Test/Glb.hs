-- | Reading a binary glTF file back in a test.
--
-- A @.glb@ is a 12-byte header, a JSON chunk and a binary chunk, each chunk
-- led by its length and its type. More than one spec needs to look inside
-- one, and a second hand-written reader would check less than this one: it
-- refuses a file whose magic, version or chunk types are wrong, so a broken
-- container fails by naming the field rather than as a missing value.
module Test.Glb (Glb (..), parseGlb, at, items, nth) where

import Data.Aeson (Value (..), decodeStrict)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Word (Word32)
import Test.Hspec

-- | A binary glTF document taken apart: the header's declared total, the JSON
-- chunk parsed, and the binary chunk as bytes.
data Glb = Glb
  { glbTotal :: Int,
    glbJsonLength :: Int,
    glbBinLength :: Int,
    glbJson :: Value,
    glbBin :: ByteString
  }

parseGlb :: ByteString -> IO Glb
parseGlb bytes = do
  BS.take 4 bytes `shouldBe` "glTF"
  word32At 4 `shouldBe` 2
  BS.take 4 (BS.drop 16 bytes) `shouldBe` "JSON"
  let jsonLen = fromIntegral (word32At 12)
      binHeader = 20 + jsonLen
  BS.take 4 (BS.drop (binHeader + 4) bytes) `shouldBe` "BIN\0"
  let binLen = fromIntegral (word32At binHeader)
  json <- maybe (fail "the JSON chunk does not parse") pure (decodeStrict (BS.take jsonLen (BS.drop 20 bytes)))
  pure
    Glb
      { glbTotal = fromIntegral (word32At 8),
        glbJsonLength = jsonLen,
        glbBinLength = binLen,
        glbJson = json,
        glbBin = BS.take binLen (BS.drop (binHeader + 8) bytes)
      }
  where
    word32At :: Int -> Word32
    word32At i = le (BS.unpack (BS.take 4 (BS.drop i bytes)))
    le [a, b, c, d] =
      fromIntegral a
        .|. (fromIntegral b `shiftL` 8)
        .|. (fromIntegral c `shiftL` 16)
        .|. (fromIntegral d `shiftL` 24)
    le _ = 0

-- | Walk into a JSON value by field name.
at :: Text -> Value -> Value
at k (Object o) = fromMaybe Null (KM.lookup (Key.fromText k) o)
at _ _ = Null

-- | The elements of a JSON array, or nothing at all for anything else.
items :: Value -> [Value]
items (Array v) = toList v
items _ = []

-- | The n-th element of a JSON array.
nth :: Int -> Value -> Value
nth i v = case drop i (items v) of
  (x : _) -> x
  [] -> Null
