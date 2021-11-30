package orm

import (
	"github.com/cosmos/cosmos-sdk/codec"
	sdk "github.com/cosmos/cosmos-sdk/types"
)

var _ Indexable = &PrimaryKeyTableBuilder{}

// NewPrimaryKeyTableBuilder creates a builder to setup a PrimaryKeyTable object.
func NewPrimaryKeyTableBuilder(prefixData byte, storeKey sdk.StoreKey, model PrimaryKeyed, cdc codec.Marshaler) (*PrimaryKeyTableBuilder, error) {
	tableBuilder, err := newTableBuilder(prefixData, storeKey, model, cdc)
	if err != nil {
		return nil, err
	}
	return &PrimaryKeyTableBuilder{
		tableBuilder: tableBuilder,
	}, nil
}

type PrimaryKeyTableBuilder struct {
	*tableBuilder
}

func (a PrimaryKeyTableBuilder) Build() PrimaryKeyTable {
	return PrimaryKeyTable{table: a.tableBuilder.Build()}

}

// PrimaryKeyed defines an object type that is aware of its immutable primary key.
type PrimaryKeyed interface {
	// PrimaryKeyFields returns the fields of the object that will make up
	// the primary key. The PrimaryKey function will encode and concatenate
	// the fields to build the primary key.
	//
	// PrimaryKey parts can be []byte, string, and integer types. []byte is
	// encoded with a length prefix, strings are null-terminated, and
	// integers are encoded using 8 byte big endian.
	//
	// IMPORTANT: []byte parts are encoded with a single byte length prefix,
	// so cannot be longer than 255 bytes.
	PrimaryKeyFields() []interface{}
	codec.ProtoMarshaler
}

// PrimaryKey returns the immutable and serialized primary key of this object.
// The primary key has to be unique within it's domain so that not two with same
// value can exist in the same table. This means PrimaryKeyFields() has to
// return a unique value for each object.
func PrimaryKey(obj PrimaryKeyed) []byte {
	fields := obj.PrimaryKeyFields()
	key, err := buildKeyFromParts(fields)
	if err != nil {
		panic(err)
	}
	return key
}

var _ TableExportable = &PrimaryKeyTable{}

// PrimaryKeyTable provides simpler object style orm methods without passing database RowIDs.
// Entries are persisted and loaded with a reference to their unique primary key.
type PrimaryKeyTable struct {
	table table
}

// Create persists the given object under their primary key. It checks if the
// key already exists and may return an `ErrUniqueConstraint`.
//
// Create iterates through the registered callbacks that may add secondary
// index keys.
func (a PrimaryKeyTable) Create(ctx HasKVStore, obj PrimaryKeyed) error {
	rowID := PrimaryKey(obj)
	return a.table.Create(ctx, rowID, obj)
}

// Update updates the given object under the primary key. It expects the key to
// exists already and fails with an `ErrNotFound` otherwise. Any caller must
// therefore make sure that this contract is fulfilled. Parameters must not be
// nil.
//
// Update iterates through the registered callbacks that may add or remove
// secondary index keys.
func (a PrimaryKeyTable) Update(ctx HasKVStore, newValue PrimaryKeyed) error {
	return a.table.Update(ctx, PrimaryKey(newValue), newValue)
}

// Set persists the given object under the rowID key. It does not check if the
// key already exists and overwrites the value if it does.
//
// Set iterates through the registered callbacks that may add secondary index
// keys.
func (a PrimaryKeyTable) Set(ctx HasKVStore, newValue PrimaryKeyed) error {
	return a.table.Set(ctx, PrimaryKey(newValue), newValue)
}

// Delete removes the object. It expects the primary key to exists already and
// fails with a `ErrNotFound` otherwise. Any caller must therefore make sure
// that this contract is fulfilled.
//
// Delete iterates through the registered callbacks that remove secondary index
// keys.
func (a PrimaryKeyTable) Delete(ctx HasKVStore, obj PrimaryKeyed) error {
	return a.table.Delete(ctx, PrimaryKey(obj))
}

// Has checks if a key exists. Panics on nil key.
func (a PrimaryKeyTable) Has(ctx HasKVStore, primaryKey RowID) bool {
	return a.table.Has(ctx, primaryKey)
}

// Contains returns true when an object with same type and primary key is persisted in this table.
func (a PrimaryKeyTable) Contains(ctx HasKVStore, obj PrimaryKeyed) bool {
	if err := assertCorrectType(a.table.model, obj); err != nil {
		return false
	}
	return a.table.Has(ctx, PrimaryKey(obj))
}

// GetOne load the object persisted for the given primary Key into the dest parameter.
// If none exists `ErrNotFound` is returned instead. Parameters must not be nil.
func (a PrimaryKeyTable) GetOne(ctx HasKVStore, primKey RowID, dest codec.ProtoMarshaler) error {
	return a.table.GetOne(ctx, primKey, dest)
}

// PrefixScan returns an Iterator over a domain of keys in ascending order. End is exclusive.
// Start is an MultiKeyIndex key or prefix. It must be less than end, or the Iterator is invalid and error is returned.
// Iterator must be closed by caller.
// To iterate over entire domain, use PrefixScan(nil, nil)
//
// WARNING: The use of a PrefixScan can be very expensive in terms of Gas. Please make sure you do not expose
// this as an endpoint to the public without further limits.
// Example:
//			it, err := idx.PrefixScan(ctx, start, end)
//			if err !=nil {
//				return err
//			}
//			const defaultLimit = 20
//			it = LimitIterator(it, defaultLimit)
//
// CONTRACT: No writes may happen within a domain while an iterator exists over it.
func (a PrimaryKeyTable) PrefixScan(ctx HasKVStore, start, end []byte) (Iterator, error) {
	return a.table.PrefixScan(ctx, start, end)
}

// ReversePrefixScan returns an Iterator over a domain of keys in descending order. End is exclusive.
// Start is an MultiKeyIndex key or prefix. It must be less than end, or the Iterator is invalid  and error is returned.
// Iterator must be closed by caller.
// To iterate over entire domain, use PrefixScan(nil, nil)
//
// WARNING: The use of a ReversePrefixScan can be very expensive in terms of Gas. Please make sure you do not expose
// this as an endpoint to the public without further limits. See `LimitIterator`
//
// CONTRACT: No writes may happen within a domain while an iterator exists over it.
func (a PrimaryKeyTable) ReversePrefixScan(ctx HasKVStore, start, end []byte) (Iterator, error) {
	return a.table.ReversePrefixScan(ctx, start, end)
}

// Export stores all the values in the table in the passed ModelSlicePtr.
func (a PrimaryKeyTable) Export(ctx HasKVStore, dest ModelSlicePtr) (uint64, error) {
	return a.table.Export(ctx, dest)
}

// Import clears the table and initializes it from the given data interface{}.
// data should be a slice of structs that implement PrimaryKeyed.
func (a PrimaryKeyTable) Import(ctx HasKVStore, data interface{}, seqValue uint64) error {
	return a.table.Import(ctx, data, seqValue)
}