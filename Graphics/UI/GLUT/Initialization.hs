-- #prune
--------------------------------------------------------------------------------
-- |
-- Module      :  Graphics.UI.GLUT.Initialization
-- Copyright   :  (c) Sven Panne 2002
-- License     :  BSD-style (see the file libraries/GLUT/LICENSE)
-- 
-- Maintainer  :  sven_panne@yahoo.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Actions and state variables in this module are used to initialize GLUT state.
-- The primary initialization routine is 'initialize', which should only be
-- called exactly once in a GLUT program. No other GLUT or OpenGL actions should
-- be called before 'initialize', apart from getting or setting the state
-- variables in this module.
--
-- The reason is that these state variables can be used to set default window
-- initialization state that might be modified by the command processing done in
-- 'initialize'. For example, 'initialWindowSize' can be set to @('WindowSize'
-- 400 400)@ before 'initialize' is called to indicate 400 by 400 is the
-- program\'s default window size. Setting the initial window size or position
-- before 'initialize' allows the GLUT program user to specify the initial size
-- or position using command line arguments.
--
--------------------------------------------------------------------------------

module Graphics.UI.GLUT.Initialization (
   -- * Primary initialization
   initialize, getArgsAndInitialize,

   -- * Initial window geometry
   initialWindowPosition, initialWindowSize,

   -- * Setting the initial display mode (I)
   DisplayMode(..), initialDisplayMode, isDisplayModePossible,

   -- * Setting the initial display mode (II)
   relationToString,   -- used only internally
   Capability(..), Relation(..), CapabilityDescription(..),
   initialDisplayCapabilities
) where

import Data.Bits ( Bits((.|.),(.&.)) )
import Data.List ( genericLength, intersperse )
import Foreign.C.String ( CString, withCString, peekCString )
import Foreign.C.Types ( CInt, CUInt )
import Foreign.Marshal.Array ( withArray0, peekArray )
import Foreign.Marshal.Utils ( with, withMany )
import Foreign.Ptr ( Ptr, nullPtr )
import Foreign.Storable ( Storable(..) )
import System.Environment ( getProgName, getArgs )
import Graphics.Rendering.OpenGL.GL.CoordTrans ( Position(..), Size(..) )
import Graphics.Rendering.OpenGL.GL.StateVar (
   SettableStateVar, makeSettableStateVar, StateVar, makeStateVar )
import Graphics.UI.GLUT.Constants
import Graphics.UI.GLUT.State ( simpleGet )

--------------------------------------------------------------------------------

-- | Given the program name and command line arguments, initialize the GLUT
-- library and negotiate a session with the window system. During this
-- process, 'initialize' may cause the termination of the GLUT program with an
-- error message to the user if GLUT cannot be properly initialized.
-- Examples of this situation include the failure to connect to the window
-- system, the lack of window system support for OpenGL, and invalid command
-- line options.
--
-- 'initialized.' also processes command line options, but the specific options
-- parsed are window system dependent. Any command line arguments which are
-- not GLUT-specific are returned.
--
-- /X Implementation Notes:/ The X Window System specific options parsed by
-- 'initialize' are as follows:
--
-- * @-display /DISPLAY/@: Specify the X server to connect to. If not specified,
--   the value of the @DISPLAY@ environment variable is used.
--
-- * @-geometry /WxH+X+Y/@: Determines where windows should be created on the
--   screen. The parameter following @-geometry@ should be formatted as a
--   standard X geometry specification. The effect of using this option is to
--   change the GLUT initial size and initial position the same as if
--   'initialWindowSize' or 'initialWindowPosition' were modified directly.
--
-- * @-iconic@: Requests all top-level windows be created in an iconic state.
--
-- * @-indirect@: Force the use of indirect OpenGL rendering contexts.
--
-- * @-direct@: Force the use of direct OpenGL rendering contexts (not all GLX
--   implementations support direct rendering contexts). A fatal error is
--   generated if direct rendering is not supported by the OpenGL
--   implementation. If neither @-indirect@ or @-direct@ are used to force a
--   particular behavior, GLUT will attempt to use direct rendering if
--   possible and otherwise fallback to indirect rendering.
--
-- * @-gldebug@: After processing callbacks and\/or events, check if there
--   are any OpenGL errors by calling 'Graphics.Rendering.OpenGL.getError'.
--   If an error is reported, print out a warning by looking up the error
--   code with 'Graphics.Rendering.OpenGL.errorString'. Using this option
--   is helpful in detecting OpenGL run-time errors.
--
-- * @-sync@: Enable synchronous X protocol transactions. This option makes
--   it easier to track down potential X protocol errors.

initialize :: String      -- ^ The program name.
           -> [String]    -- ^ The command line arguments
           -> IO [String] -- ^ Non-GLUT command line arguments
initialize prog args =
   with (1 + genericLength args) $ \argcBuf ->
   withMany withCString (prog : args) $ \argvPtrs ->
   withArray0 nullPtr argvPtrs $ \argvBuf -> do
   glutInit argcBuf argvBuf
   newArgc <- peek argcBuf
   newArgvPtrs <- peekArray (fromIntegral newArgc) argvBuf
   newArgv <- mapM peekCString newArgvPtrs
   return $ tail newArgv

foreign import CALLCONV unsafe "glutInit" glutInit ::
   Ptr CInt -> Ptr CString -> IO ()

-- | Convenience action: Initialize GLUT, returning the program name and any
-- non-GLUT command line arguments.

getArgsAndInitialize :: IO (String, [String])
getArgsAndInitialize = do
   prog <- getProgName
   args <- getArgs
   nonGLUTArgs <- initialize prog args
   return (prog, nonGLUTArgs)

--------------------------------------------------------------------------------

-- | Controls the /initial window position/.  Windows created by
-- 'Graphics.UI.GLUT.Window.createWindow' will be requested to be created with
-- the current /initial window position/. The initial value of the /initial
-- window position/ GLUT state is @'Size' (-1) (-1)@. If either the X or Y
-- component of the /initial window position/ is negative, the actual window
-- position is left to the window system to determine.
--
-- The intent of the /initial window position/ is to provide a suggestion to
-- the window system for a window\'s initial position. The window system is
-- not obligated to use this information. Therefore, GLUT programs should not
-- assume the window was created at the specified position.

initialWindowPosition :: StateVar Position
initialWindowPosition =
   makeStateVar getInitialWindowPosition setInitialWindowPosition

getInitialWindowPosition :: IO Position
getInitialWindowPosition = do
   x <- simpleGet fromIntegral glut_INIT_WINDOW_X
   y <- simpleGet fromIntegral glut_INIT_WINDOW_Y
   return $ Position x y

setInitialWindowPosition :: Position -> IO ()
setInitialWindowPosition (Position x y) =
    glutInitWindowPosition (fromIntegral x) (fromIntegral y)

foreign import CALLCONV unsafe "glutInitWindowPosition" glutInitWindowPosition
   :: CInt -> CInt -> IO ()

--------------------------------------------------------------------------------

-- | Controls the /initial window size/.  Windows created by
-- 'Graphics.UI.GLUT.Window.createWindow' will be requested to be created with
-- the current /initial window size/. The initial value of the /initial window
-- size/ GLUT state is @'Size' 300 300@. If either the width or the height
-- component of the /initial window size/ is non-positive, the actual window
-- size is left to the window system to determine.
--
-- The intent of the /initial window size/ is to provide a suggestion to the
-- window system for a window\'s initial size. The window system is not
-- obligated to use this information. Therefore, GLUT programs should not
-- assume the window was created at the specified size. A GLUT program should
-- use the window\'s reshape callback to determine the true size of the
-- window.

initialWindowSize :: StateVar Size
initialWindowSize = makeStateVar getInitialWindowSize setInitialWindowSize

getInitialWindowSize :: IO Size
getInitialWindowSize = do
   w <- simpleGet fromIntegral glut_INIT_WINDOW_WIDTH
   h <- simpleGet fromIntegral glut_INIT_WINDOW_HEIGHT
   return $ Size w h

setInitialWindowSize :: Size -> IO ()
setInitialWindowSize (Size w h) =
   glutInitWindowSize (fromIntegral w) (fromIntegral h)

foreign import CALLCONV unsafe "glutInitWindowSize" glutInitWindowSize ::
   CInt -> CInt -> IO ()

--------------------------------------------------------------------------------

-- | A single aspect of a window which is to be created, used in conjunction
-- with 'initialDisplayMode'.

data DisplayMode
   = RGBA        -- ^ Select an RGBA mode window. This is the default if neither 'RGBA' nor 'Index' are specified.
   | RGB         -- ^ An alias for 'RGBA'.
   | Index       -- ^ Select a color index mode window. This overrides 'RGBA' if it is also specified.
   | Single      -- ^ Select a single buffered window. This is the default if neither 'Double' nor 'Single' are specified.
   | Double      -- ^ Select a double buffered window. This overrides 'Single' if it is also specified.
   | Accum       -- ^ Select a window with an accumulation buffer.
   | Alpha       -- ^ Select a window with an alpha component to the color buffer(s).
   | Depth       -- ^ Select a window with a depth buffer.
   | Stencil     -- ^ Select a window with a stencil buffer.
   | Multisample -- ^ Select a window with multisampling support. If multisampling is not available, a non-multisampling
                 --   window will automatically be chosen. Note: both the OpenGL client-side and server-side implementations
                 --   must support the @GLX_SAMPLE_SGIS@ extension for multisampling to be available.
   | Stereo      -- ^ Select A Stereo Window.
   | Luminance   -- ^ Select a window with a \"luminance\" color model. This model provides the functionality of OpenGL\'s
                 --   RGBA color model, but the green and blue components are not maintained in the frame buffer. Instead
                 --   each pixel\'s red component is converted to an index between zero and  'Graphics.UI.GLUT.State.getColormapEntryCount'
                 --   and looked up in a per-window color map to determine the color of pixels within the window. The initial
                 --   colormap of 'Luminance' windows is initialized to be a linear gray ramp, but can be modified with GLUT\'s
                 --   colormap actions. /Implementation Notes:/ 'Luminance' is not supported on most OpenGL platforms.
   deriving ( Eq, Ord, Enum, Bounded )

marshalDisplayMode :: DisplayMode -> CUInt
marshalDisplayMode m = case m of
   RGBA        -> glut_RGBA
   RGB         -> glut_RGB
   Index       -> glut_INDEX
   Single      -> glut_SINGLE
   Double      -> glut_DOUBLE
   Accum       -> glut_ACCUM
   Alpha       -> glut_ALPHA
   Depth       -> glut_DEPTH
   Stencil     -> glut_STENCIL
   Multisample -> glut_MULTISAMPLE
   Stereo      -> glut_STEREO
   Luminance   -> glut_LUMINANCE

--------------------------------------------------------------------------------

-- | Controls the /initial display mode/ used when creating top-level windows,
-- subwindows, and overlays to determine the OpenGL display mode for the
-- to-be-created window or overlay.
--
-- Note that 'RGBA' selects the RGBA color model, but it does not request any
-- bits of alpha (sometimes called an /alpha buffer/ or /destination alpha/)
-- be allocated. To request alpha, specify 'Alpha'. The same applies to
-- 'Luminance'.

initialDisplayMode :: StateVar [DisplayMode]
initialDisplayMode = makeStateVar getInitialDisplayMode setInitialDisplayMode

getInitialDisplayMode :: IO [DisplayMode]
getInitialDisplayMode = simpleGet i2dms glut_INIT_DISPLAY_MODE

i2dms :: CInt -> [DisplayMode]
i2dms = fromBitfield marshalDisplayMode . fromIntegral

fromBitfield :: (Enum a, Bounded a, Bits b) => (a -> b) -> b -> [a]
fromBitfield marshal bitfield =
   [ c | c <- [ minBound .. maxBound ],  (bitfield .&. marshal c) /= 0 ]

setInitialDisplayMode :: [DisplayMode] -> IO ()
setInitialDisplayMode = glutInitDisplayMode . toBitfield marshalDisplayMode

toBitfield :: (Bits b) => (a -> b) -> [a] -> b
toBitfield marshal = foldl (.|.) 0 . map marshal

foreign import CALLCONV unsafe "glutInitDisplayMode" glutInitDisplayMode ::
   CUInt -> IO ()

-- | Test whether the /current display mode/ is supported or not.

isDisplayModePossible :: IO Bool
isDisplayModePossible = simpleGet (/= 0) glut_DISPLAY_MODE_POSSIBLE

--------------------------------------------------------------------------------

-- | Capabilities for 'initialDisplayCapabilities', most of them are extensions
-- of 'DisplayMode'\'s constructors.

data Capability
   = RGBA'        -- ^ Number of bits of red, green, blue, and alpha in the RGBA
                  --   color buffer. Default is \"'IsAtLeast' @1@\" for red,
                  --   green, blue, and alpha capabilities, and \"'IsEqualTo'
                  --   @1@\" for the RGBA color model capability.
   | RGB'         -- ^ Number of bits of red, green, and blue in the RGBA color
                  --   buffer and zero bits of alpha color buffer precision.
                  --   Default is \"'IsAtLeast' @1@\" for the red, green, and
                  --   blue capabilities, and \"'IsNotLessThan' @0@\" for alpha
                  --   capability, and \"'IsEqualTo' @1@\" for the RGBA color
                  --   model capability.
   | Red          -- ^ Red color buffer precision in bits. Default is
                  --   \"'IsAtLeast' @1@\".
   | Green        -- ^ Green color buffer precision in bits. Default is
                  --   \"'IsAtLeast' @1@\".
   | Blue         -- ^ Blue color buffer precision in bits. Default is
                  --   \"'IsAtLeast' @1@\".
   | Index'       -- ^ Boolean if the color model is color index or not. True is
                  --   color index. Default is \"'IsAtLeast' @1@\".
   | Buffer       -- ^ Number of bits in the color index color buffer. Default
                  --   is \"'IsAtLeast' @1@\".
   | Single'      -- ^ Boolean indicate the color buffer is single buffered.
                  --   Defaultis \"'IsEqualTo' @1@\".
   | Double'      -- ^ Boolean indicating if the color buffer is double
                  --   buffered. Default is \"'IsEqualTo' @1@\".
   | AccA         -- ^ Red, green, blue, and alpha accumulation buffer precision
                  --   in  bits. Default is \"'IsAtLeast' @1@\" for red, green,
                  --   blue, and alpha capabilities.
   | Acc          -- ^ Red, green, and green accumulation buffer precision in
                  --   bits and zero bits of alpha accumulation buffer precision.
                  --   Default is \"'IsAtLeast' @1@\" for red, green, and blue
                  --   capabilities, and \"'IsNotLessThan' @0@\" for the alpha
                  --   capability.
   | Alpha'       -- ^ Alpha color buffer precision in bits. Default is
                  --   \"'IsAtLeast' @1@\".
   | Depth'       -- ^ Number of bits of precsion in the depth buffer. Default
                  --   is \"'IsAtLeast' @12@\".
   | Stencil'     -- ^ Number of bits in the stencil buffer. Default is
                  --   \"'IsNotLessThan' @1@\".
   | Samples      -- ^ Indicates the number of multisamples to use based on
                  --   GLX\'s @SGIS_multisample@ extension (for antialiasing).
                  --   Default is \"'IsNotGreaterThan' @4@\". This default means
                  --   that a GLUT application can request multisampling if
                  --   available by simply specifying \"'With' 'Samples'\".
   | Stereo'      -- ^ Boolean indicating the color buffer is supports
                  --   OpenGL-style stereo. Default is \"'IsEqualTo' @1@\".
   | Luminance'   -- ^ Number of bits of red in the RGBA and zero bits of green,
                  --   blue (alpha not specified) of color buffer precision.
                  --   Default is \"'IsAtLeast' @1@\" for the red capabilitis,
                  --   and \"'IsEqualTo' @0@\" for the green and blue
                  --   capabilities, and \"'IsEqualTo' @1@\" for the RGBA color
                  --   model capability, and, for X11, \"'IsEqualTo' @1@\" for
                  --   the 'XStaticGray' capability. SGI InfiniteReality (and
                  --   other future machines) support a 16-bit luminance (single
                  --   channel) display mode (an additional 16-bit alpha channel
                  --   can also be requested). The red channel maps to gray
                  --   scale and green and blue channels are not available. A
                  --   16-bit precision luminance display mode is often
                  --   appropriate for medical imaging applications. Do not
                  --   expect many machines to support extended precision
                  --   luminance display modes.
   | Num          -- ^ A special capability name indicating where the value
                  --   represents the Nth frame buffer configuration matching
                  --   the description string. When not specified,
                  --   'initialDisplayCapabilitiesString' also returns the first
                  --   (best matching) configuration. 'Num' requires a relation
                  --   and numeric value.
   | Conformant   -- ^ Boolean indicating if the frame buffer configuration is
                  --   conformant or not. Conformance information is based on
                  --   GLX\'s @EXT_visual_rating@ extension if supported. If the
                  --   extension is not supported, all visuals are assumed
                  --   conformant. Default is \"'IsEqualTo' @1@\".
   | Slow         -- ^ Boolean indicating if the frame buffer configuration is
                  --   slow or not. Slowness information is based on GLX\'s
                  --   @EXT_visual_rating@ extension if supported. If the
                  --   extension is not supported, all visuals are assumed fast.
                  --   Note that slowness is a relative designation relative to
                  --   other frame buffer configurations available. The intent
                  --   of the slow capability is to help programs avoid frame
                  --   buffer configurations that are slower (but perhaps higher
                  --   precision) for the current machine. Default is
                  --   \"'IsAtLeast' @0@\". This default means that slow visuals
                  --   are used in preference to fast visuals, but fast visuals
                  --   will still be allowed.
   | Win32PFD     -- ^ Only recognized on GLUT implementations for Win32, this
                  --   capability name matches the Win32 Pixel Format Descriptor
                  --   by number. 'Win32PFD' can only be used with 'Where'.
   | XVisual      -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, this capability name matches the X visual ID by
                  --   number. 'XVisual' requires a relation and numeric value.
   | XStaticGray  -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @StaticGray@.
                  --   Default is \"'IsEqualTo' @1@\".
   | XGrayScale   -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @GrayScale@. Default
                  --   is \"'IsEqualTo' @1@\".
   | XStaticColor -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @StaticColor@.
                  --   Default is \"'IsEqualTo' @1@\".
   | XPseudoColor -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @PsuedoColor@.
                  --   Default is \"'IsEqualTo' @1@\".
   | XTrueColor   -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @TrueColor@. Default
                  --   is \"'IsEqualTo' @1@\".
   | XDirectColor -- ^ Only recongized on GLUT implementations for the X Window
                  --   System, boolean indicating if the frame buffer
                  --   configuration\'s X visual is of type @DirectColor@.
                  --   Default is \"'IsEqualTo' @1@\".
   deriving ( Eq, Ord )

capabilityToString :: Capability -> String
capabilityToString RGBA'        = "rgba"
capabilityToString RGB'         = "rgb"
capabilityToString Red          = "red"
capabilityToString Green        = "green"
capabilityToString Blue         = "blue"
capabilityToString Index'       = "index"
capabilityToString Buffer       = "buffer"
capabilityToString Single'      = "single"
capabilityToString Double'      = "double"
capabilityToString AccA         = "acca"
capabilityToString Acc          = "acc"
capabilityToString Alpha'       = "alpha"
capabilityToString Depth'       = "depth"
capabilityToString Stencil'     = "stencil"
capabilityToString Samples      = "samples"
capabilityToString Stereo'      = "stereo"
capabilityToString Luminance'   = "luminance"
capabilityToString Num          = "num"
capabilityToString Conformant   = "conformant"
capabilityToString Slow         = "slow"
capabilityToString Win32PFD     = "win32pfd"
capabilityToString XVisual      = "xvisual"
capabilityToString XStaticGray  = "xstaticgray"
capabilityToString XGrayScale   = "xgrayscale"
capabilityToString XStaticColor = "xstaticcolor"
capabilityToString XPseudoColor = "xpseudocolor"
capabilityToString XTrueColor   = "xtruecolor"
capabilityToString XDirectColor = "xdirectcolor"

-- | Relation between a 'Capability' and a numeric value.

data Relation
   = IsEqualTo        -- ^ Equal.
   | IsNotEqualTo     -- ^ Not equal.
   | IsLessThan       -- ^ Less than and preferring larger difference (the least
                      --   is best).
   | IsNotGreaterThan -- ^ Less than or equal and preferring larger difference
                      --   (the least is best).
   | IsGreaterThan    -- ^ Greater than and preferring larger differences (the
                      --   most is best).
   | IsAtLeast        -- ^ Greater than or equal and preferring more instead of
                      --   less. This relation is useful for allocating
                      --   resources like color precision or depth buffer
                      --   precision where the maximum precision is generally
                      --   preferred. Contrast with 'IsNotLessThan' relation.
   | IsNotLessThan    -- ^ Greater than or equal but preferring less instead of
                      --   more. This relation is useful for allocating
                      --   resources such as stencil bits or auxillary color
                      --   buffers where you would rather not over-allocate.
   deriving ( Eq, Ord )

relationToString :: Relation -> String
relationToString IsEqualTo        = "="
relationToString IsNotEqualTo     = "!="
relationToString IsLessThan       = "<"
relationToString IsNotGreaterThan = "<="
relationToString IsGreaterThan    = ">"
relationToString IsAtLeast        = ">="
relationToString IsNotLessThan    = "~"

-- | A single capability description for 'initialDisplayCapabilities'.

data CapabilityDescription
   = Where Capability Relation CInt -- ^ A description of a capability with a
                                    --   specific relation to a numeric value.
   | With  Capability               -- ^ When the relation and numeric value are
                                    --   not specified, each capability has a
                                    --   different default, see the different
                                    --   constructors of 'Capability'.
   deriving ( Eq, Ord )

capabilityDescriptionToString ::  CapabilityDescription -> String
capabilityDescriptionToString (Where c r i) =
   capabilityToString c ++ relationToString r ++ show i
capabilityDescriptionToString (With c) = capabilityToString c

-- | Controls the /initial display mode/ used when creating top-level windows,
-- subwindows, and overlays to determine the OpenGL display mode for the
-- to-be-created window or overlay. It is described by a list of zero or more
-- capability descriptions, which are translated into a set of criteria used to
-- select the appropriate frame buffer configuration. The criteria are matched
-- in strict left to right order of precdence. That is, the first specified
-- criterion (leftmost) takes precedence over the later criteria for non-exact
-- criteria ('IsGreaterThan', 'IsLessThan', etc.). Exact criteria ('IsEqualTo',
-- 'IsNotEqualTo') must match exactly so precedence is not relevant.
--
-- Unspecified capability descriptions will result in unspecified criteria being
-- generated. These unspecified criteria help 'initialDisplayCapabilities'
-- behave sensibly with terse display mode descriptions.
--
-- Here is an example using 'initialDisplayCapabilities':
--
-- @
--    initialDisplayCapabilities $= [ With  RGB\',
--                                    Where Depth\' IsAtLeast 16,
--                                    With  Samples,
--                                    Where Stencil\' IsNotLessThan 2,
--                                    With  Double\' ]
-- @
--
-- The above call requests a window with an RGBA color model (but requesting
-- no bits of alpha), a depth buffer with at least 16 bits of precision but
-- preferring more, multisampling if available, at least 2 bits of stencil
-- (favoring less stencil to more as long as 2 bits are available), and double
-- buffering.

initialDisplayCapabilities :: SettableStateVar [CapabilityDescription]
initialDisplayCapabilities =
   makeSettableStateVar $ \caps ->
      withCString
         (concat . intersperse " " . map capabilityDescriptionToString $ caps)
         glutInitDisplayString

foreign import CALLCONV unsafe "glutInitDisplayString" glutInitDisplayString ::
  CString -> IO ()
