--!strict

local PromiseTypes = require(script.Parent.PromiseTypes)
local Signal = require(script.Parent.Parent.Signal)

--[=[
	@type LoadMethod { ForceLoad: string, Steal: string, Cancel: string }
	@within DataKeep

	### "ForceLoad" (default)

	Attempts to load the Keep. If the Keep is session-locked, it will either be released for that remote server or "stolen" if it's not responding (possibly in dead lock).


	### "Steal"

	Loads keep immediately, ignoring an existing remote session lock and applying a session lock for this session.


	### "Cancel"

	Cancels the load of the Keep.
]=]

export type loadMethod = {
	ForceLoad: string,
	Steal: string,
	Cancel: string,
}

--[=[
	@type LogLevel { All: string, Warn: string, Error: string, None: string }
	@within DataKeep

	### "All"

	Logs everything.


	### "Warn" (default)

	Logs warnings and errors.


	### "Error"

	Logs errors only.


	### "None"

	No logs.
]=]

export type logLevel = {
	All: string,
	Warn: string,
	Error: string,
	None: string,
}

--[=[
	@type StoreInfo { Name: string, Scope: string? }
	@within Store

	Table format for a store's info in [.GetStore()](#GetStore).
]=]

export type storeInfo = {
	Name: string,
	Scope: string?,
}

--[=[
	@type unreleasedHandler (Session) -> string
	@within Store

	Used to determine how to handle an session locked Keep.

	:::info
	Check [LoadMethod] for more info.
	:::
]=]

export type unreleasedHandler = (session: session) -> string -- function for any purposes: logging, whitelist only certain places, etc.

export type dataTemplate<T> = T

export type wrapper<T> = T

--[=[
	@type StoreBase {}
	@within Store
]=]

type storeBase<T, R> = {
	_storeInfo: storeInfo,
	_dataTemplate: dataTemplate<T>,

	_datastore: DataStore,
	_isMockEnabled: boolean,

	_preLoad: (data: data<T>) -> data<T>,
	_preSave: (data: data<T>) -> data<T>,

	_wrapper: wrapper<R>,

	_globalStateProcessor: globalStateProcessor,

	validate: (data: data<T>) -> (boolean, string?),

	Identify: (self: storeBase<T, R>) -> string,

	LoadKeep: (self: storeBase<T, R>, key: string, unreleasedHandler: unreleasedHandler?) -> PromiseTypes.TypedPromise<keep<T, R>>,
	ViewKeep: (self: storeBase<T, R>, key: string, version: string?) -> PromiseTypes.TypedPromise<viewOnlyKeep<T, R>>,
	RemoveKeep: (self: storeBase<T, R>, key: string) -> PromiseTypes.TypedPromise<keepStruct<T>, DataStoreKeyInfo>,

	PreLoad: (self: storeBase<T, R>, callback: (data: data<T>) -> data<T>) -> (),
	PreSave: (self: storeBase<T, R>, callback: (data: data<T>) -> data<T>) -> (),

	PostGlobalUpdate: (self: storeBase<T, R>, key: string, updateHandler: (globalUpdates: globalUpdatesClass) -> ()) -> PromiseTypes.TypedPromise<keepStruct<T>, DataStoreKeyInfo>,
}

--[=[
	@type MockStore StoreBase
	@within Store

	MockStores are used to mirror the real store, but doesn't save data.
]=]

export type mockStore<T, R = {}> = storeBase<T, R>

--[=[
	@type Store StoreBase & { Mock: MockStore }
	@within Store

	Stores are used to load and save Keeps from a [DataStoreService:GetDataStore()](https://create.roblox.com/docs/reference/engine/classes/DataStoreService#GetDataStore).
]=]

export type store<T, R = {}> = storeBase<T, R> & {
	Mock: mockStore<T, R>,
}

--[=[
	@type Session { PlaceId: number, JobId: string }
	@within Keep
]=]

export type session = {
	PlaceId: number,
	JobId: string,
}

--[=[
	@type Metadata { ActiveSession: Session?, ForceLoad: Session?, LastUpdate: number, Created: number, LoadCount: number }
	@within Keep
]=]

export type metadata = {
	ActiveSession: session?,

	ForceLoad: session?, -- the session stealing the session lock, if any

	IsOverwriting: boolean?, -- true if .ActiveSession is found during :Overwrite()
	ReleaseSessionOnOverwrite: boolean?,

	LastUpdate: number,
	Created: number,
	LoadCount: number,
}

export type userIds = { number }
export type data<T> = dataTemplate<T>

export type keepStruct<T> = {
	Data: data<T>,
	GlobalUpdates: globalUpdates,
}

export type setVersionReturn<T> = {
	Data: data<T>,
	Metadata: metadata,
	GlobalUpdates: globalUpdates,
	UserIds: userIds,
}

export type keepBase<T, R> = keepStruct<T> & {
	_store: store<T, R>,
	_datastore: DataStore,
	_key: string,

	_dataTemplate: dataTemplate<T>,

	_keyInfo: DataStoreKeyInfo,

	_viewOnly: boolean,

	_releasing: boolean,
	_released: boolean,
	_destroyed: boolean,

	Metadata: metadata,
	UserIds: userIds,

	IsActive: (self: keepBase<T, R>) -> boolean,
	Identify: (self: keepBase<T, R>) -> string,
	GetKeyInfo: (self: keepBase<T, R>) -> DataStoreKeyInfo,

	Destroy: (self: keepBase<T, R>) -> (),

	Reconcile: (self: keepBase<T, R>) -> (),
	AddUserId: (self: keepBase<T, R>, userId: number) -> (),
	RemoveUserId: (self: keepBase<T, R>, userId: number) -> (),

	GetVersions: (self: keepBase<T, R>, minDate: number?, maxDate: number?) -> PromiseTypes.TypedPromise<iterator>,
	SetVersion: (self: keepBase<T, R>, version: string, migrateProcessor: ((versionKeep: viewOnlyKeep<T, R>) -> viewOnlyKeep<T, R>)?) -> PromiseTypes.TypedPromise<setVersionReturn<T>>,

	GetActiveGlobalUpdates: (self: keepBase<T, R>) -> { globalUpdate },
	GetLockedGlobalUpdates: (self: keepBase<T, R>) -> { globalUpdate },
} & R

--[=[
	@type Keep { Data: { [string]: any }, Metadata: Metadata, GlobalUpdates: GlobalUpdates, UserIds: { number }, OnGlobalUpdate: Signal<GlobalUpdateData, number>, Released: Signal, ReleaseFailed: Signal, Saved: Signal, SaveFailed: Signal, Overwritten: Signal<boolean> }
	@within Keep
]=]

export type keep<T, R = {}> = keepBase<T, R> & {
	_lastSaveAttempt: number,

	_pendingGlobalLocks: { number },
	_pendingGlobalLockRemoves: { number },

	Released: Signal.ScriptSignal<>,
	ReleaseFailed: Signal.ScriptSignal<>,
	Saved: Signal.ScriptSignal<>,
	SaveFailed: Signal.ScriptSignal<>,
	Overwritten: Signal.ScriptSignal<boolean>,
	OnGlobalUpdate: Signal.ScriptSignal<globalUpdateData, number>,

	Save: (self: keep<T, R>) -> PromiseTypes.TypedPromise<()>,
	Release: (self: keep<T, R>) -> PromiseTypes.TypedPromise<()>,

	ClearLockedUpdate: (self: keep<T, R>, id: number) -> PromiseTypes.TypedPromise<()>,
}

export type viewOnlyKeep<T, R = {}> = keepBase<T, R> & {
	Overwrite: (self: viewOnlyKeep<T, R>, shouldKeepExistingSession: boolean?) -> PromiseTypes.TypedPromise<()>,
}

export type iterator = {
	Current: () -> DataStoreObjectVersionInfo?,
	Next: () -> DataStoreObjectVersionInfo?,
	Previous: () -> DataStoreObjectVersionInfo?,
	PageUp: () -> (),
	PageDown: () -> (),
	SkipEnd: () -> (),
	SkipStart: () -> (),
}

--[=[
	@type GlobalUpdateData any
	@within GlobalUpdates
]=]

export type globalUpdateData<T = any> = T

--[=[
	@type GlobalUpdate { Id: number, Data: GlobalUpdateData }
	@within GlobalUpdates
]=]

export type globalUpdate<T = any> = {
	Id: number,
	Data: globalUpdateData<T>,
}

--[=[
	@type GlobalUpdates { Id: number, Updates: { GlobalUpdate & { Locked: boolean } } }
	@within GlobalUpdates

	```Id``` is the most recent update index.
]=]

export type globalUpdates<T = any> = {
	Id: number,
	Updates: { globalUpdate<T> & { Locked: boolean } },
}

export type globalUpdatesClass<T = any> = {
	_updates: globalUpdates<T>,

	AddGlobalUpdate: (self: globalUpdatesClass<T>, globalUpdateData: globalUpdateData<T>) -> PromiseTypes.TypedPromise<number>,
	ChangeActiveUpdate: (self: globalUpdatesClass<T>, updateId: number, globalUpdateData: globalUpdateData<T>) -> PromiseTypes.TypedPromise<()>,
	RemoveActiveUpdate: (self: globalUpdatesClass<T>, updateId: number) -> PromiseTypes.TypedPromise<()>,
	GetActiveUpdates: (self: globalUpdatesClass<T>) -> { globalUpdate<T> },
}

export type globalStateProcessor = (globalUpdateData: globalUpdateData, lock: () -> (), remove: () -> ()) -> ()

return nil
