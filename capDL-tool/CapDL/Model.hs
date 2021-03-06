--
-- Copyright 2014, NICTA
--
-- This software may be distributed and modified according to the terms of
-- the BSD 2-Clause license. Note that NO WARRANTY is provided.
-- See "LICENSE_BSD2.txt" for details.
--
-- @TAG(NICTA_BSD)
--

{-# LANGUAGE DeriveDataTypeable #-}
module CapDL.Model where

import Prelude ()
import Prelude.Compat
import Data.Map
import Data.Set
import Data.Data

-- Supported architectures:
data Arch = IA32 | ARM11 deriving (Eq, Show)

-- Access rights of capabilities. Not all capability types support all rights.
data Rights = Read
            | Write
            | Grant
            deriving (Eq, Show, Enum, Ord, Typeable, Data)

type CapRights = Set Rights

allRights :: CapRights
allRights = Data.Set.fromList [Read, Write, Grant]

--
-- Object identifiers.
--
-- Currently, each object is described by a string (its name), possibly
-- followed by a word (an index). The latter feature allows arrays of
-- objects to be specified without having to give them explicit names
-- (for instance, when declaring large numbers of frames for a process).
--
-- These may later be converted to a type variable.
--
type ObjID = (String, Maybe Word)


type Asid = (Word, Word)

--
-- Capabilities.
--
-- Each cap has a type (what the cap does), and a bunch of attributes
-- (such as the rights, what object the capability gives access to,
-- etc).
--
data Cap
        = NullCap
        | UntypedCap { capObj :: ObjID }
        | EndpointCap {
            capObj :: ObjID,
            capBadge :: Word,
            capRights :: CapRights }
        | NotificationCap {
            capObj :: ObjID,
            capBadge :: Word,
            capRights :: CapRights }
        | ReplyCap { capObj :: ObjID }
        | MasterReplyCap { capObj :: ObjID }
        | CNodeCap {
            capObj :: ObjID,
            capGuard :: Word,
            capGuardSize :: Word }
        | TCBCap { capObj :: ObjID }
        | IRQControlCap
        | IRQHandlerCap { capObj :: ObjID }
        | DomainCap

        -- arch specific caps, ARM11 and IA32 merged
        | FrameCap {
            capObj :: ObjID,
            capRights :: CapRights,
            capMaybeAsid :: Maybe Asid,
            capCached :: Bool,
            capMaybeMapping :: Maybe (ObjID, Word) }
        | PTCap {
            capObj :: ObjID,
            capMaybeAsid :: Maybe Asid }
        | PDCap {
            capObj :: ObjID,
            capMaybeAsid :: Maybe Asid }
        | ASIDControlCap -- only one ASIDTable in the system
        | ASIDPoolCap {
            capObj :: ObjID,
            capAsid :: Asid }

        -- IA32 specific caps
        | IOPortsCap {
            capObj :: ObjID,
            capPorts :: Set Word }
        | IOSpaceMasterCap -- can mint to any IOSpaceCap
        | IOSpaceCap { capObj :: ObjID }
        | IOPTCap { capObj :: ObjID }
        | VCPUCap { capObj :: ObjID }
        deriving (Eq, Ord, Show)



-- Kernel Objects

type CapMap a = Map a Cap

data TCBExtraInfo = TCBExtraInfo {
    ipcBufferAddr :: Word,
    ip :: Maybe Word,
    sp :: Maybe Word,
    elf :: Maybe String,
    prio :: Maybe Integer }
    deriving (Eq, Show)

--
-- Kernel objects in memory.
--
-- This type represents attributes associated with in-memory kernel
-- objects. The type parameter 'a' is the type used to name caps. (For
-- example, a C implementation would use a 32-bit word, while another
-- implementation may pre-decode caps in a list of words).
--
data KernelObject a
    = Endpoint
    | Notification
    | TCB {
        slots :: CapMap a,
        faultEndpoint :: Maybe Word,
        extraInfo :: Maybe TCBExtraInfo,
        dom :: Integer,
        initArguments :: [Word] }
    | CNode {
        slots :: CapMap a,
        sizeBits :: Word }
    | Untyped {
        maybeSizeBits :: Maybe Word,
        maybePaddr :: Maybe Word }

-- arch specific objects, ARM11 and IA32 mixed
    | ASIDPool { slots :: CapMap a }
    | PT { slots :: CapMap a }
    | PD { slots :: CapMap a }
    | Frame {
        vmSizeBits :: Word,
        paddr :: Maybe Word }

-- IA32 specific objects
    | IOPorts { size :: Word } -- only one in the system
    | IODevice {
        slots :: CapMap a,
        domainID :: Word,
        pciDevice :: (Word, Word, Word)}
    | IOPT {
        slots :: CapMap a,
        level :: Word }
    | VCPU

    deriving (Eq, Show)


data KOType
    = Endpoint_T
    | Notification_T
    | TCB_T
    | CNode_T
    | Untyped_T
    | IrqSlot_T
    | ASIDPool_T
    | PT_T
    | PD_T
    | Frame_T
    | IOPorts_T
    | IODevice_T
    | IOPT_T
    | VCPU_T
    deriving (Show, Eq, Enum)

--
-- A reference to a capability.
--
-- The ObjID is the kernel object the capability sits within (which will
-- be either a CNode or a TCB), and the Word represents the slot
-- (indexed from 0).
--
type CapRef = (ObjID, Word)

-- The name of a cap, used when copying caps.
type CapName = ObjID

type ObjMap a = Map ObjID (KernelObject a)

type IRQMap = Map Word ObjID

type ObjSet = Set ObjID

type CoverMap = Map ObjID ObjSet

type CDT = Map CapRef CapRef

--
-- The state of the system.
--
-- The system state consists of:
--
--   1. The architecture in use;
--   2. The objects currently present;
--   3. The global irq node; and
--   4. The cap derivation tree (which allows us to determine which
--      objects are derived from which other objects)
--
-- Two forms of model exist. The first is an abstract model where
-- CSpaces are assumed to be flat. Caps are identified by a Word
-- pointing somewhere in the CSpace.
--
-- The second model is a more concrete object where caps are assumed to
-- be in a tree of CNodes. Caps are identified by a list of Words
-- indicating the offsets of the target cap in each level of the tree.
--
data Model a
  = Model {
    arch :: Arch,
    objects :: ObjMap a,
    irqNode :: IRQMap,
    cdt :: CDT,
    untypedCovers :: CoverMap }
  deriving Show


data Idents cap_id = Idents {
    cap_ids :: Map cap_id CapRef
} deriving Show

type CopyMap = Map CapRef CapName

--
-- Each TCB contains five cap slots. The following constants define the
-- slot numbers in which they will be found if the TCB is treated as
-- a CNode.
--
tcbCTableSlot :: Word
tcbCTableSlot = 0

tcbVTableSlot :: Word
tcbVTableSlot = 1

tcbReplySlot :: Word
tcbReplySlot = 2

tcbCallerSlot :: Word
tcbCallerSlot = 3

tcbIPCBufferSlot :: Word
tcbIPCBufferSlot = 4

tcbFaultEPSlot :: Word
tcbFaultEPSlot = 5

--
-- The string used when defining an IOSpaceMasterCap, an ASIDControlCap,
-- an IRQControlCap or a DomainCap.
--
ioSpaceMaster :: String
ioSpaceMaster = "io_space_master"

asidControl :: String
asidControl = "asid_control"

irqControl :: String
irqControl = "irq_control"

domain :: String
domain = "domain"

--
-- Determine if the given capability points to an object.
--
hasObjID :: Cap -> Bool
hasObjID NullCap = False
hasObjID IOSpaceMasterCap = False
hasObjID ASIDControlCap = False
hasObjID IRQControlCap = False
hasObjID DomainCap = False
hasObjID _  = True

--
-- Get the object a particular cap points to.
--
-- This function is partial, not all caps point to an object.
--
objID :: Cap -> ObjID
objID = capObj

--
-- Determine if the given cap has rights.
--
hasRights :: Cap -> Bool
hasRights (NotificationCap {})   = True
hasRights (EndpointCap {})        = True
hasRights (FrameCap {})           = True
hasRights _                       = False

--
-- Determine if the given object has capability slots.
--
hasSlots :: KernelObject a -> Bool
hasSlots (TCB {})       = True
hasSlots (CNode {})     = True
hasSlots (ASIDPool {})  = True
hasSlots (PT {})        = True
hasSlots (PD {})        = True
hasSlots (IODevice {})  = True
hasSlots (IOPT {})      = True
hasSlots _              = False

