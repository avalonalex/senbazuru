-- | Named panel points and orders in the study manifest. Geometry checking
-- lives in Senbazuru.Origami.Contact; this adapter only reads the study's JSON.
module ContactSpec (PanelTag (..), ContactSpec (..)) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Text (Text)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))

data PanelTag = PanelTag {tagName :: !Text, tagAt :: !V2}
  deriving stock (Eq, Show)

instance FromJSON PanelTag where
  parseJSON = withObject "panel name and material point" $ \o -> do
    name <- o .: "name"
    point <- o .: "at"
    case point of
      [x, y] -> pure (PanelTag name (V2 x y))
      _ -> fail "panel at needs two material coordinates"

instance ToJSON PanelTag where
  toJSON (PanelTag name (V2 x y)) = object ["name" .= name, "at" .= [x, y]]

data ContactSpec = ContactSpec
  {orderDirection :: !V3, namedPanels :: ![PanelTag], panelOrders :: ![(Text, Text)]}
  deriving stock (Eq, Show)

instance FromJSON ContactSpec where
  parseJSON = withObject "panel contact requirements" $ \o -> do
    direction <- o .: "direction"
    case direction of
      [x, y, z] -> ContactSpec (V3 x y z) <$> o .: "panels" <*> o .: "orders"
      _ -> fail "contact direction needs three coordinates"

instance ToJSON ContactSpec where
  toJSON (ContactSpec (V3 x y z) panels orders) =
    object
      ["direction" .= [x, y, z], "panels" .= panels, "orders" .= orders]
