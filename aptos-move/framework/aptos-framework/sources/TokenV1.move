/// This module provides the foundation for Tokens.
module AptosFramework::TokenV1 {
    use Std::ASCII::{String, Self};
    use Std::Errors;
    use Std::Event::{Self, EventHandle};
    use Std::Signer;
    use Std::Vector;

    use AptosFramework::Table::{Self, Table};
    use AptosFramework::PropertyList::{Self, PropertyList};

    const TOKEN_MAX_MUTABLE_IND: u64 = 0;
    const TOKEN_URI_MUTABLE_IND: u64 = 1;
    const TOKEN_DESCRIPTION_MUTABLE_IND: u64 = 2;
    const TOKEN_ROYALTY_MUTABLE_IND: u64 = 3;
    const TOKEN_PROPERTY_MUTABLE_IND: u64 = 4;

    const COLLECTION_DESCRIPTION_MUTABLE_IND: u64 = 0;
    const COLLECTION_URI_MUTABLE_IND: u64 = 1;
    const COLLECTION_MAX_MUTABLE_IND: u64 = 2;

    const EALREADY_HAS_BALANCE: u64 = 0;
    const EBALANCE_NOT_PUBLISHED: u64 = 1;
    const ECOLLECTIONS_NOT_PUBLISHED: u64 = 2;
    const ECOLLECTION_NOT_PUBLISHED: u64 = 3;
    const ECOLLECTION_ALREADY_EXISTS: u64 = 4;
    const ECREATE_WOULD_EXCEED_MAXIMUM: u64 = 5;
    const EINSUFFICIENT_BALANCE: u64 = 6;
    const EINVALID_COLLECTION_NAME: u64 = 7;
    const EINVALID_TOKEN_MERGE: u64 = 8;
    const EMINT_WOULD_EXCEED_MAXIMUM: u64 = 9;
    const ENO_BURN_CAPABILITY: u64 = 10;
    const ENO_MINT_CAPABILITY: u64 = 11;
    const ETOKEN_ALREADY_EXISTS: u64 = 12;
    const ETOKEN_NOT_PUBLISHED: u64 = 13;
    const ETOKEN_STORE_NOT_PUBLISHED: u64 = 14;

    //
    // Core data structures for holding tokens
    //

    struct Token has store {
        id: TokenId,
        value: u64,
    }

    struct TokenId has store, copy, drop {
        tokendata_id: TokenDataId,
        serial_number: u64
    }

    struct TokenDataId has copy, drop, store {
        // The creator of this token
        creator: address,
        // The collection or set of related tokens within the creator's account
        collection: String,
        // Unique name within a collection within the creator's account
        name: String,
    }

    /// The royalty of a token
    struct Royalty has copy, drop, store {
        royalty_points_nominator: u64,
        royalty_points_denominator: u64,
        // if the token is jointly owned by multiple creators,
        // the group of creators should create a shared account.
        // the creator_account will be the shared account address.
        resource_account: address,
    }

    // This config specifies whether fields in the Collection are mutable
    struct CollectionMutabilityConfig has copy, store, drop {
        description: bool,
        // URL for additional information /media
        uri: bool,
        // Optional maximum number of tokens allowed within this collections
        maximum: bool,
    }

    // This config specifies whether fields in the TokenData are mutable
    struct TokenMutabilityConfig has copy, store, drop {
        maximum: bool,
        uri: bool,
        royalty: bool,
        description: bool,
        default_property_list: bool,
    }

    struct PropertyValue has store, copy, drop {
        type: String,
        value: vector<vector<u8>>,
    }

    /// The data associated with the Tokens
    struct TokenData has store {
        id: TokenDataId,
        maximum: u64,
        // Total number of this type of Token
        supply: u64,
        // The max serial number we should have for the token
        largest_serial_number: u64,
        // URL for additional information / media
        uri: String,
        // the royalty of the token
        royalty: Royalty,
        // The name of this Token
        name: String,
        // Describes this Token
        description: String,
        // the properties can be used to hold any custom attributes
        default_property_list: PropertyList,
        mutability_config: TokenMutabilityConfig,
    }

    /// Represents token resources owned by token owner
    struct TokenStore has key {
        tokens: Table<TokenId, Token>,
        token_data: Table<TokenId, PropertyList>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    /// Set of data sent to the event stream during a receive
    struct DepositEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    /// Set of data sent to the event stream during a withdrawal
    struct WithdrawEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    /// token creation event id of token created
    struct CreateTokenEvent has copy, store, drop {
        id: TokenId,
        initial_balance: u64,
    }

    /// mint token event. This event triggered when creator adds more supply to existing token
    struct MintTokenEvent has drop, store {
        id: TokenId,
        amount: u64,
    }

    //
    // Core data structures for creating and maintaining tokens
    //

    /// Represent collection and token metadata for a creator
    struct Collections has key {
        collections: Table<String, Collection>,
        token_data: Table<TokenDataId, TokenData>,
        burn_capabilities: Table<TokenId, BurnCapability>,
        mint_capabilities: Table<TokenId, MintCapability>,
        create_collection_events: EventHandle<CreateCollectionEvent>,
        create_token_events: EventHandle<CreateTokenEvent>,
        mint_token_events: EventHandle<MintTokenEvent>,
    }

    /// Represent the collection metadata
    struct Collection has store {
        // Describes the collection
        description: String,
        // Unique name within this creators account for this collection
        name: String,
        // URL for additional information /media
        uri: String,
        // Total number of distinct Tokens tracked by the collection
        count: u64,
        // Optional maximum number of tokens allowed within this collections
        maximum: u64,
        mutability_config: CollectionMutabilityConfig,
    }

    /// create collection event with creator address and collection name
    struct CreateCollectionEvent has drop, store {
        creator: address,
        collection_name: String,
        uri: String,
        description: String,
        maximum:u64,
    }

    /// Capability required to mint tokens.
    struct MintCapability has store {
        token_id: TokenId,
    }

    /// Capability required to burn tokens.
    struct BurnCapability has store {
        token_id: TokenId,
    }

    //
    // Creator Script functions
    //

    public(script) fun create_collection_script(
        creator: &signer,
        name: vector<u8>,
        description: vector<u8>,
        uri: vector<u8>,
        maximum: u64,
        mutate_setting: vector<bool>
    ) acquires Collections {

        create_collection(
            creator,
            ASCII::string(name),
            ASCII::string(description),
            ASCII::string(uri),
            maximum,
            mutate_setting
        );
    }

    public(script) fun create_token_script(
        creator: &signer,
        collection: vector<u8>,
        name: vector<u8>,
        description: vector<u8>,
        balance: u64,
        maximum: u64,
        uri: vector<u8>,
        royalty_resource_account: address,
        royalty_points_denominator: u64,
        royalty_points_nominator: u64,
        token_mutate_setting: vector<bool>,
        property_keys: vector<String>,
        property_values: vector<vector<u8>>,
        property_types: vector<String>
    ) acquires Collections, TokenStore {
        create_token(
            creator,
            ASCII::string(collection),
            ASCII::string(name),
            ASCII::string(description),
            balance,
            maximum,
            ASCII::string(uri),
            royalty_resource_account,
            royalty_points_denominator,
            royalty_points_nominator,
            token_mutate_setting,
            property_keys,
            property_values,
            property_types,
        );
    }

    public(script) fun mint(
        account: &signer,
        token_data_address: address,
        collection: vector<u8>,
        name: vector<u8>,
        amount: u64,
        property_keys: vector<String>,
        property_values: vector<vector<u8>>,
        property_types: vector<String>
    ) acquires Collections, TokenStore {

        /*
            TODO: signer and capability checking
        */
        mint_token(
            account,
            create_token_data_id(token_data_address, ASCII::string(collection), ASCII::string(name)),
            amount,
            property_keys,
            property_values,
            property_types
        );
    }

    //
    // Transaction Script functions
    //

    public(script) fun direct_transfer_script(
        sender: &signer,
        receiver: &signer,
        creators_address: address,
        collection: vector<u8>,
        name: vector<u8>,
        edition: u64,
        amount: u64,
    ) acquires TokenStore {
        let token_id = create_token_id_raw(creators_address, collection, name, edition);
        direct_transfer(sender, receiver, token_id, amount);
    }

    public(script) fun initialize_token_script(account: &signer) {
        initialize_token_store(account);
    }

    //
    // Public functions for holding tokens
    //

    /// Deposit the token balance into the owner's account and emit an event.
    public fun deposit_token(
        account: &signer,
        token: Token
    ) acquires TokenStore {
        let account_addr = Signer::address_of(account);
        initialize_token_store(account);
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;
        if (!Table::contains(tokens, token.id)) {
            initialize_token(account, token.id);
        };

        direct_deposit(account_addr, token)
    }

    /// Deposit the token balance into the recipients account and emit an event.
    public fun  direct_deposit(account_addr: address, token: Token) acquires TokenStore {
        let token_store = borrow_global_mut<TokenStore>(account_addr);

        Event::emit_event<DepositEvent>(
            &mut token_store.deposit_events,
            DepositEvent { id: token.id, amount: token.value },
        );

        direct_deposit_without_event(account_addr, token);
    }

    /// Deposit the token balance into the recipients account without emitting an event.
    public fun direct_deposit_without_event(account_addr: address, token: Token) acquires TokenStore {
        assert!(
            exists<TokenStore>(account_addr),
            Errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let token_store = borrow_global_mut<TokenStore>(account_addr);

        assert!(
            Table::contains(&token_store.tokens, token.id),
            Errors::not_published(EBALANCE_NOT_PUBLISHED),
        );
        let recipient_token = Table::borrow_mut(&mut token_store.tokens, token.id);

        merge(recipient_token, token);
    }

    public fun direct_transfer(
        sender: &signer,
        receiver: &signer,
        token_id: TokenId,
        amount: u64,
    ) acquires TokenStore {
        let token = withdraw_token(sender, token_id, amount);
        deposit_token(receiver, token)
    }

    public fun initialize_token(account: &signer, token_id: TokenId) acquires TokenStore {
        let account_addr = Signer::address_of(account);
        assert!(
            exists<TokenStore>(account_addr),
            Errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;

        assert!(
            !Table::contains(tokens, token_id),
            Errors::already_published(EALREADY_HAS_BALANCE),
        );
        Table::add(tokens, token_id, Token { value : 0, id: token_id });
    }

    public fun initialize_token_store(account: &signer) {
        if (!exists<TokenStore>(Signer::address_of(account))) {
            move_to(
                account,
                TokenStore {
                    tokens: Table::new(),
                    token_data: Table::new(),
                    deposit_events: Event::new_event_handle<DepositEvent>(account),
                    withdraw_events: Event::new_event_handle<WithdrawEvent>(account),
                },
            );
        }
    }

    public fun merge(dst_token: &mut Token, source_token: Token) {
        assert!(&dst_token.id == &source_token.id, Errors::invalid_argument(EINVALID_TOKEN_MERGE));
        dst_token.value = dst_token.value + source_token.value;
        let Token { id: _, value: _ } = source_token;
    }

    public fun token_id(token: &Token): &TokenId {
        &token.id
    }

    /// Transfers `amount` of tokens from `from` to `to`.
    public fun transfer(
        from: &signer,
        id: TokenId,
        to: address,
        amount: u64,
    ) acquires TokenStore {
        let token = withdraw_token(from, id ,amount);
        direct_deposit(to, token);
        transfer_token_properties(Signer::address_of(from), to, id);
    }

    public fun withdraw_token(
        account: &signer,
        id: TokenId,
        amount: u64,
    ): Token acquires TokenStore {
        let account_addr = Signer::address_of(account);
        let token_store = borrow_global_mut<TokenStore>(account_addr);
        Event::emit_event<WithdrawEvent>(
            &mut token_store.withdraw_events,
            WithdrawEvent { id, amount },
        );
        withdraw_without_event_internal(account_addr, id, amount)
    }


    fun withdraw_without_event_internal(
        account_addr: address,
        id: TokenId,
        amount: u64
    ): Token acquires TokenStore {
        assert!(
            exists<TokenStore>(account_addr),
            Errors::not_published(ETOKEN_STORE_NOT_PUBLISHED),
        );
        let tokens = &mut borrow_global_mut<TokenStore>(account_addr).tokens;
        assert!(
            Table::contains(tokens, id),
            Errors::not_published(EBALANCE_NOT_PUBLISHED),
        );
        let balance = &mut Table::borrow_mut(tokens, id).value;
        *balance = *balance - amount;


        Token { id, value: amount}
    }

    //
    // Public functions for creating and maintaining tokens
    //

    /// Create a new collection to hold tokens
    public fun create_collection(
        creator: &signer,
        name: String,
        description: String,
        uri: String,
        maximum: u64,
        mutate_setting: vector<bool>
    ) acquires Collections {
        let account_addr = Signer::address_of(creator);
        if (!exists<Collections>(account_addr)) {
            move_to(
                creator,
                Collections {
                    collections: Table::new(),
                    token_data: Table::new(),
                    burn_capabilities: Table::new(),
                    mint_capabilities: Table::new(),
                    create_collection_events:  Event::new_event_handle<CreateCollectionEvent>(creator),
                    create_token_events: Event::new_event_handle<CreateTokenEvent>(creator),
                    mint_token_events: Event::new_event_handle<MintTokenEvent>(creator),
                },
            )
        };

        let collections = &mut borrow_global_mut<Collections>(account_addr).collections;

        assert!(
            !Table::contains(collections, name),
            Errors::already_published(ECOLLECTION_ALREADY_EXISTS),
        );

        let mutability_config = create_collection_mutability_config(&mutate_setting);
        let collection = Collection {
            description,
            name: *&name,
            uri,
            count: 0,
            maximum,
            mutability_config
        };

        Table::add(collections, name, collection);
        let collection_handle =  borrow_global_mut<Collections>(account_addr);
        Event::emit_event<CreateCollectionEvent>(
            &mut collection_handle.create_collection_events,
            CreateCollectionEvent {
                creator: account_addr,
                collection_name: *&name,
                uri,
                description,
                maximum,

            }
        );
    }

    public fun create_tokendata(
        account: &signer,
        collection: String,
        name: String,
        description: String,
        amount: u64,
        maximum: u64,
        uri: String,
        royalty_resource_account: address,
        royalty_points_denominator: u64,
        royalty_points_nominator: u64,
        token_mutate_config: TokenMutabilityConfig,
        property_keys: vector<String>,
        property_values: vector<vector<u8>>,
        property_types: vector<String>
    ): TokenDataId acquires Collections {
        let account_addr = Signer::address_of(account);
        assert!(
            exists<Collections>(account_addr),
            Errors::not_published(ECOLLECTIONS_NOT_PUBLISHED),
        );
        let collections = borrow_global_mut<Collections>(account_addr);

        let token_data_id = create_token_data_id(account_addr, collection, name);

        assert!(
            Table::contains(&collections.collections, token_data_id.collection),
            Errors::already_published(ECOLLECTION_NOT_PUBLISHED),
        );
        assert!(
            !Table::contains(&collections.token_data, token_data_id),
            Errors::already_published(ETOKEN_ALREADY_EXISTS),
        );

        let collection = Table::borrow_mut(&mut collections.collections, token_data_id.collection);
        collection.count = collection.count + 1;

        assert!(
            collection.maximum >= collection.count,
            ECREATE_WOULD_EXCEED_MAXIMUM,
        );

        let supply = amount;


        let token_data = TokenData {
            id: token_data_id,
            maximum,
            supply,
            largest_serial_number: 0,
            uri,
            royalty: Royalty {
                royalty_points_denominator,
                royalty_points_nominator,
                resource_account: royalty_resource_account,
            },
            name,
            description,
            default_property_list: PropertyList::new(&property_keys, &property_values, &property_types),
            mutability_config: token_mutate_config,
        };

        Table::add(&mut collections.token_data, token_data_id, token_data);
        token_data_id
    }

    public fun create_token_mutability_config(mutate_setting: &vector<bool>): TokenMutabilityConfig {
        TokenMutabilityConfig {
            maximum: *Vector::borrow(mutate_setting, TOKEN_MAX_MUTABLE_IND),
            uri: *Vector::borrow(mutate_setting, TOKEN_URI_MUTABLE_IND),
            royalty: *Vector::borrow(mutate_setting, TOKEN_ROYALTY_MUTABLE_IND),
            description: *Vector::borrow(mutate_setting, TOKEN_DESCRIPTION_MUTABLE_IND),
            default_property_list: *Vector::borrow(mutate_setting, TOKEN_PROPERTY_MUTABLE_IND)
        }
    }

    public fun create_collection_mutability_config(mutate_setting: &vector<bool>): CollectionMutabilityConfig {
        CollectionMutabilityConfig {
            description: *Vector::borrow(mutate_setting, COLLECTION_DESCRIPTION_MUTABLE_IND),
            uri: *Vector::borrow(mutate_setting, COLLECTION_URI_MUTABLE_IND),
            maximum: *Vector::borrow(mutate_setting, COLLECTION_MAX_MUTABLE_IND),
        }
    }

    //create new edition with new metadata
    //create new edition without new metadata
    //mint new for existing edition [don't support this]

    public fun create_token(
        account: &signer,
        collection: String,
        name: String,
        description: String,
        balance: u64,
        maximum: u64,
        uri: String,
        royalty_resource_account: address,
        royalty_points_denominator: u64,
        royalty_points_nominator: u64,
        mutate_setting: vector<bool>,
        property_keys: vector<String>,
        property_values: vector<vector<u8>>,
        property_types: vector<String>
    ): TokenId acquires Collections, TokenStore {

        /*
            TODO: capability and signer check
       */
        let token_mut_config = create_token_mutability_config(&mutate_setting);

        let tokendata_id = create_tokendata(
            account,
            collection,
            name,
            description,
            0, // haven't minted token yet
            maximum,
            uri,
            royalty_resource_account,
            royalty_points_denominator,
            royalty_points_nominator,
            token_mut_config,
            property_keys,
            property_values,
            property_types
        );

        let token_id = mint_token(
            account,
            tokendata_id,
            balance,
            Vector::empty<String>(),
            Vector::empty<vector<u8>>(),
            Vector::empty<String>()
        );

        token_id
    }

    fun get_properties_to_be_updated(
        token_data: &TokenData,
        keys: &vector<String>,
        values: &vector<vector<u8>>,
        types: &vector<String>
    ): PropertyList {

        let res_keys = Vector::empty<String>();
        let res_vals = Vector::empty<vector<u8>>();
        let res_types = Vector::empty<String>();
        let default_properties = &token_data.default_property_list;
        let i = 0;
        while (i < Vector::length(keys)){
            let k = Vector::borrow(keys, i);
            let v = Vector::borrow(values, i);
            let t = Vector::borrow(types, i);
            if (PropertyList::contains(default_properties, k) ) {
                if ( PropertyList::get_type(default_properties, k) == *t && PropertyList::get_value(default_properties, k) != *v ) {
                    Vector::push_back(&mut res_keys, *k);
                    Vector::push_back(&mut res_vals, *v);
                    Vector::push_back(&mut res_types, *t);
                };
            };
            i = i + 1;
        };
        PropertyList::new(&res_keys, &res_vals, &res_types)
    }

    public fun mint_token(
        account: &signer,
        token_data_id: TokenDataId,
        amount: u64,
        keys: vector<String>,
        values: vector<vector<u8>>,
        types:  vector<String>
    ): TokenId acquires Collections, TokenStore {

       /*
       TODO: capability and signer check
       */
        assert!(Vector::length(&keys) == Vector::length(&values), 1);
        assert!(Vector::length(&types) == Vector::length(&values), 1);

        let creator_addr = token_data_id.creator;
        let all_token_data = &mut borrow_global_mut<Collections>(creator_addr).token_data;
        let token_data = Table::borrow_mut(all_token_data, token_data_id);

        assert!(token_data.supply + amount <= token_data.maximum, 1);

        token_data.supply = token_data.supply + amount;
        token_data.largest_serial_number = token_data.largest_serial_number + 1;
        let largest_serial_number = token_data.largest_serial_number;


        let token_id = create_token_id(token_data_id, largest_serial_number);
        deposit_token(account,
            Token {
                id: token_id,
                value: amount
            }
        );

        let property_list  = get_properties_to_be_updated(token_data, &keys, &values, &types);
        add_token_properties(account, token_id, property_list);

        token_id
    }

    public fun add_token_properties(
        account: &signer,
        id: TokenId,
        token_properties: PropertyList
    ) acquires TokenStore{
        assert!(exists<TokenStore>(Signer::address_of(account)), 1);
        let property_table = &mut borrow_global_mut<TokenStore>(
            Signer::address_of(account)).token_data;
        assert!(!Table::contains(property_table, id), 1);
        Table::add(property_table, id, token_properties);
    }

    fun transfer_token_properties(from: address, to: address, id: TokenId) acquires TokenStore{
        assert!(exists<TokenStore>(from), 1);
        assert!(exists<TokenStore>(to), 1);

        let source = borrow_global_mut<TokenStore>(from);
        let properites = Table::remove(&mut source.token_data, id);

        let dst = borrow_global_mut<TokenStore>(to);
        Table::add(&mut dst.token_data, id, properites);
    }


    public fun create_token_id (tokendata_id: TokenDataId, serial_number: u64): TokenId {
        TokenId {
            tokendata_id,
            serial_number
        }
    }
    public fun create_token_data_id(
        creator: address,
        collection: String,
        name: String,
    ): TokenDataId {
        TokenDataId { creator, collection, name }
    }

    public fun create_token_id_raw(
        creator: address,
        collection: vector<u8>,
        name: vector<u8>,
        serial_number: u64
    ): TokenId {
        TokenId {
            tokendata_id: create_token_data_id(creator, ASCII::string(collection), ASCII::string(name)),
            serial_number
        }
    }


    public fun balance_of(owner: address, id: TokenId): u64 acquires  TokenStore {
        let token_store = borrow_global<TokenStore>(owner);
        if (Table::contains(&token_store.tokens, id)) {
            Table::borrow(&token_store.tokens, id).value
        } else {
            0
        }
    }


    // ****************** TEST-ONLY FUNCTIONS **************

    #[test(creator = @0x1, owner = @0x2)]
    public fun create_withdraw_deposit_token(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 1, 1, 1);

        let token = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token);
    }

    #[test(creator = @0xCC, owner = @0xCB)]
    public fun create_withdraw_deposit(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 5, 5);

        let token_0 = withdraw_token(&creator, token_id, 1);
        let token_1 = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token_0);
        deposit_token(&creator, token_1);
        let token_2 = withdraw_token(&creator, token_id, 1);
        deposit_token(&owner, token_2);
    }

    #[test(creator = @0x1)]
    #[expected_failure] // (abort_code = 5)]
    public fun test_collection_maximum(creator: signer) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 2, 1);
        let default_keys = vector<String>[ASCII::string(b"attack"), ASCII::string(b"num_of_use")];
        let default_vals = vector<vector<u8>>[b"10", b"5"];
        let default_types = vector<String>[ASCII::string(b"integer"), ASCII::string(b"integer")];
        let mutate_setting = vector<bool>[false, false, false, false, false];

        create_token(
            &creator,
            token_id.tokendata_id.collection,
            ASCII::string(b"Token"),
            ASCII::string(b"Hello, Token"),
            100,
            2,
            ASCII::string(b"https://aptos.dev"),
            Signer::address_of(&creator),
            100,
            0,
            mutate_setting,
            default_keys,
            default_vals,
            default_types,
        );

    }

    #[test(creator = @0x1, owner = @0x2)]
    public(script) fun direct_transfer_test(
        creator: signer,
        owner: signer,
    ) acquires Collections, TokenStore {
        let token_id = create_collection_and_token(&creator, 2, 2, 2);
        direct_transfer(&creator, &owner, token_id, 1);
        let token = withdraw_token(&owner, token_id, 1);
        deposit_token(&creator, token);
    }

    #[test_only]
    public fun get_collection_name(): String {
        ASCII::string(b"Hello, World")
    }

    #[test_only]
    public fun get_token_name(): String {
        ASCII::string(b"Token")
    }

    #[test_only]
    public fun create_collection_and_token(
        creator: &signer,
        amount: u64,
        collection_max: u64,
        token_max: u64,
    ): TokenId acquires Collections, TokenStore {

        let mutate_setting = vector<bool>[false, false, false];

        create_collection(
            creator,
            get_collection_name(),
            ASCII::string(b"Collection: Hello, World"),
            ASCII::string(b"https://aptos.dev"),
            collection_max,
            mutate_setting
        );

        let default_keys = vector<String>[ASCII::string(b"attack"), ASCII::string(b"num_of_use")];
        let default_vals = vector<vector<u8>>[b"10", b"5"];
        let default_types = vector<String>[ASCII::string(b"integer"), ASCII::string(b"integer")];
        let mutate_setting = vector<bool>[false, false, false, false, false];
        create_token(
            creator,
            get_collection_name(),
            get_token_name(),
            ASCII::string(b"Hello, Token"),
            amount,
            token_max,
            ASCII::string(b"https://aptos.dev"),
            Signer::address_of(creator),
            100,
            0,
            mutate_setting,
            default_keys,
            default_vals,
            default_types,

        )
    }

    #[test(creator = @0xFF)]
    fun test_create_events_generation(creator: signer) acquires Collections, TokenStore {
        create_collection_and_token(&creator, 1, 2, 1);
        let collections = borrow_global<Collections>(Signer::address_of(&creator));
        assert!(Event::get_event_handle_counter(&collections.create_collection_events) == 1, 1);
        // TODO assert!(Event::get_event_handle_counter(&collections.create_token_events) == 1, 1);
    }

    #[test(creator = @0xAF, owner= @0xBB)]
    fun test_create_token_from_tokendata(creator: &signer, owner: &signer) acquires Collections, TokenStore {

        create_collection_and_token(creator, 2, 4, 4);
        let token_data_id = create_token_data_id(
            Signer::address_of(creator),
            get_collection_name(),
            get_token_name());

        let new_keys = vector<String>[
            ASCII::string(b"attack"), ASCII::string(b"num_of_use"),  ASCII::string(b"wrong_name")];
        let new_vals = vector<vector<u8>>[
            b"1", b"1", b"wrong_val"];
        let new_types = vector<String>[
            ASCII::string(b"integer"), ASCII::string(b"integer"),  ASCII::string(b"string")];

        let token_id = mint_token(
            owner,
            token_data_id,
            1,
            new_keys,
            new_vals,
            new_types
        );

        let token_store = borrow_global_mut<TokenStore>(Signer::address_of(owner));

        assert!(token_id.serial_number == 2, 1);
        assert!(Table::length(&token_store.tokens) == 1, 1);

        //
        let properties = Table::borrow(&token_store.token_data, token_id);
        assert!(PropertyList::size(properties) == 2, 1);
        assert!(PropertyList::get_value(properties, & ASCII::string(b"attack")) == b"1", 1);
        assert!(PropertyList::get_value(properties, & ASCII::string(b"num_of_use")) == b"1", 1);
    }
}