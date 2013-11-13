-- |
-- Copyright: 2013 (C) Amgen, Inc
{-# Language ExistentialQuantification #-}
{-# LANGUAGE PolyKinds  #-}
module H.HVal
  ( HVal
  , IsSEXP(..)
  -- * Conversion
  , fromHVal
  , safeFromHVal
  , someHVal
  , toHVal
  -- * Arithmetics
  , rplus
  , rminus
  , rmult
  , rfrac
  ) where

import qualified Language.R as R
import qualified Foreign.R  as R

import Control.Applicative
import Control.Monad ( forM_ )
import Data.Some
import Foreign ( newForeignPtr_, pokeElemOff )
import System.IO.Unsafe ( unsafePerformIO )

-- Temporary
import qualified Data.Vector.Storable as V
import Data.List ( intercalate )

-- | Runtime universe of R Values
data HVal = forall a . SEXP (R.SEXP a)
          | HLam2 (HVal -> HVal)

instance Show HVal where
    show (SEXP s)  = unsafePerformIO $ do
      let s' = R.SEXP . R.unSEXP $ s :: R.SEXP (R.Vector Double)
      l <- R.length s'
      v <- flip V.unsafeFromForeignPtr0 l <$> (newForeignPtr_ =<< R.real s')
      return $ "[1] " ++ (intercalate " " (map show $ V.toList v))
    show (HLam2 _) = "HLam2 {..}"

-- | Project from HVal to R SEXP.
--
-- Note that this function is partial.
fromHVal :: HVal -> Some R.SEXP
fromHVal (SEXP x) = Some x
fromHVal _        = error "toSEXP: not an SEXP"

-- | Safe version of 'toSEXP'.
safeFromHVal :: HVal -> Maybe (Some R.SEXP)
safeFromHVal (SEXP x) = Just (Some x)
safeFromHVal _        = Nothing

someHVal :: Some R.SEXP -> HVal
someHVal (Some x) = SEXP x

toHVal :: R.SEXP a -> HVal
toHVal x = SEXP x

--------------------------------------------------------------------------------
-- Arithmetic subset of H                                                     --
--------------------------------------------------------------------------------
instance Num HVal where
    fromInteger x = someHVal (mkSEXP (fromInteger x :: Double))
    a + b = someHVal (rplus  (fromHVal a) (fromHVal b))
    a - b = someHVal (rminus (fromHVal a) (fromHVal b))
    a * b = someHVal (rmult  (fromHVal a) (fromHVal b))
    abs _ = error "unimplemented."
    signum _ = error "unimplemented."

instance Fractional HVal where
    fromRational x = someHVal (mkSEXP (fromRational x :: Double))
    a / b = someHVal (rfrac (fromHVal a) (fromHVal b))

rplus, rminus, rmult, rfrac :: Some R.SEXP -> Some R.SEXP -> Some R.SEXP
rplus  (Some x) (Some y) = Some $ R.r2 "+" x y
rminus (Some x) (Some y) = Some $ R.r2 "-" x y
rmult  (Some x) (Some y) = Some $ R.r2 "*" x y
rfrac  (Some x) (Some y) = Some $ R.r2 "/" x y


-- | Represents a value that can be converted into S Expression
class IsSEXP a where
  mkSEXP :: a -> Some R.SEXP

instance IsSEXP Double where
  mkSEXP x = Some $ unsafePerformIO $ do
    v  <- R.allocVector R.Real 1
    pt <- R.real v
    pokeElemOff pt 0 (fromRational . toRational $ x)
    return v

instance IsSEXP [Double] where
  mkSEXP x = Some $ unsafePerformIO $ do
      v  <- R.allocVector R.Real l
      pt <- R.real v
      forM_ (zip x [0..]) $ \(g,i) -> do
          pokeElemOff pt i g
      return v
    where
      l = length x