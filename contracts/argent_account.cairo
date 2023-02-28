#[contract]
mod ArgentAccount {
    use array::ArrayTrait;
    use contracts::asserts::assert_only_self;
    use contracts::StorageAccessEscape;
    use contracts::EscapeSerde;
    use zeroable::Zeroable;
    use ecdsa::check_ecdsa_signature;
    use starknet::get_block_info;
    use traits::Into;
    use box::unbox;

    const ERC165_IERC165_INTERFACE_ID: felt = 0x01ffc9a7;
    const ERC165_ACCOUNT_INTERFACE_ID: felt = 0xa66bd575;
    const ERC165_OLD_ACCOUNT_INTERFACE_ID: felt = 0x3943f10f;

    const ESCAPE_SECURITY_PERIOD: u64 = 604800_u64; // 7 * 24 * 60 * 60;  // 7 days

    const ESCAPE_TYPE_GUARDIAN: felt = 1;
    const ESCAPE_TYPE_SIGNER: felt = 2;

    /////////////////////
    // STORAGE
    /////////////////////

    #[derive(Copy)]
    struct Escape {
        active_at: u64,
        escape_type: felt, // TODO Change to enum? ==> Can't do ATM because would have to impl partialEq, update storage, etc etc
    }

    struct Storage {
        signer: felt,
        guardian: felt,
        guardian_backup: felt,
        escape: Escape,
    }

    /////////////////////
    // EVENTS
    /////////////////////

    #[event]
    fn account_created(account: felt, key: felt, guardian: felt, guardian_backup: felt) {}

    #[event]
    fn transaction_executed(hash: felt, response: Array<felt>) {}

    #[event]
    fn escape_signer_triggered(active_at: u64) {}

    #[event]
    fn signer_escaped(new_signer: felt) {}

    #[event]
    fn escape_guardian_triggered(active_at: felt) {}

    #[event]
    fn guardian_escaped(new_guardian: felt) {}

    #[event]
    fn escape_canceled() {}

    /////////////////////
    // EXTERNAL FUNCTIONS
    /////////////////////

    #[external]
    fn initialize(new_signer: felt, new_guardian: felt, new_guardian_backup: felt) {
        // check that we are not already initialized
        assert(signer::read() == 0, 'argent/already-initialized');
        // check that the target signer is not zero
        assert(new_signer != 0, 'argent/null-signer');
        // initialize the account
        signer::write(new_signer);
        guardian::write(new_guardian);
        guardian_backup::write(new_guardian_backup);
    // account_created(starknet::get_contract_address(), new_signer, new_guardian, new_guardian_backup);
    }

    #[external]
    fn change_signer(new_signer: felt) {
        assert_only_self();
        assert(new_signer != 0, 'argent/null-signer');
        // update the signer
        signer::write(new_signer);
    }

    #[external]
    fn change_guardian(new_guardian: felt) {
        assert_only_self();
        assert_valid_guardian_backup(new_guardian);

        // update the guardian
        guardian::write(new_guardian);
    }

    #[external]
    fn change_guardian_backup(new_guardian_backup: felt) {
        assert_only_self();
        assert_guardian_set();

        guardian_backup::write(new_guardian_backup);
    }

    // TODO Shouldn't we specify who will be the new signer, and allow him to take ownership when time is over?
    // Ref https://twitter.com/bytes032/status/1628697044326969345
    // But then it means that if the escape isn't cancel, after timeout he can take the ownership at ANY time.
    #[external]
    fn trigger_escape_signer() {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_signer();

        // store new escape
        let active_at = unbox(get_block_info()).block_timestamp + ESCAPE_SECURITY_PERIOD;
        // TODO Since timestamp is a u64, and escape type 1 small felt, we can pack those two values and use 1 storage slot
        escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_SIGNER });
    // escape_signer_triggered(active_at);
    }

    #[external]
    fn trigger_escape_guardian() {
        assert_only_self();
        assert_guardian_set();

        // store new escape
        let active_at = unbox(get_block_info()).block_timestamp + ESCAPE_SECURITY_PERIOD;
        escape::write(Escape { active_at, escape_type: ESCAPE_TYPE_GUARDIAN });
    // escape_guardian_triggered(active_at);
    }

    #[external]
    fn escape_signer(new_signer: felt) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_SIGNER);
        assert(new_signer != 0, 'argent/null-signer');

        // TODO Shouldn't we check new_signer != guardian?
        clear_escape();
        signer::write(new_signer);
    // signer_escaped(new_signer);

    }

    #[external]
    fn escape_guardian(new_guardian: felt) {
        assert_only_self();
        assert_guardian_set();
        assert_can_escape_for_type(ESCAPE_TYPE_GUARDIAN);
        assert(new_guardian != 0, 'argent/null-guardian');

        clear_escape();
        guardian::write(new_guardian);
    // guardian_escaped(new_guardian);

    }


    #[external]
    fn cancel_escape() {
        assert_only_self();
        assert(escape::read().active_at != 0_u64, 'argent/no-active-escape');

        clear_escape();
    // escape_canceled();
    }

    /////////////////////
    // VIEW FUNCTIONS
    /////////////////////

    #[view]
    fn get_signer() -> felt {
        signer::read()
    }

    #[view]
    fn get_guardian() -> felt {
        guardian::read()
    }

    #[view]
    fn get_guardian_backup() -> felt {
        guardian_backup::read()
    }

    #[view]
    fn get_escape() -> Escape {
        escape::read()
    }

    // ERC165
    #[view]
    fn supports_interface(interface_id: felt) -> bool {
        interface_id == ERC165_IERC165_INTERFACE_ID | interface_id == ERC165_ACCOUNT_INTERFACE_ID | interface_id == ERC165_OLD_ACCOUNT_INTERFACE_ID
    }

    // ERC1271
    #[view]
    fn is_valid_signature(hash: felt, signatures: Array<felt>) -> bool {
        let is_valid_signer = is_valid_signer_signature(hash, @signatures);
        let is_valid_guardian = is_valid_guardian_signature(hash, @signatures);
        is_valid_signer & is_valid_guardian
    }

    fn is_valid_signer_signature(hash: felt, signatures: @Array<felt>) -> bool {
        assert(signatures.len() >= 2_usize, 'argent/invalid-signature-length');
        let signature_r = *(signatures.at(0_usize));
        let signature_s = *(signatures.at(1_usize));
        check_ecdsa_signature(hash, signer::read(), signature_r, signature_s)
    }

    fn is_valid_guardian_signature(hash: felt, signatures: @Array<felt>) -> bool {
        let guardian_ = guardian::read();
        if guardian_ == 0 {
            assert(signatures.len() == 2_usize, 'argent/invalid-signature-length');
            return true;
        }
        assert(signatures.len() == 4_usize, 'argent/invalid-signature-length');
        let signature_r = *(signatures.at(2_usize));
        let signature_s = *(signatures.at(3_usize));
        let is_valid_guardian_signature = check_ecdsa_signature(
            hash, guardian_, signature_r, signature_s
        );
        if is_valid_guardian_signature {
            return true;
        }
        check_ecdsa_signature(hash, guardian_backup::read(), signature_r, signature_s)
    }

    /////////////////////
    // UTILS
    /////////////////////

    #[inline(always)]
    fn clear_escape() {
        escape::write(Escape { active_at: 0_u64, escape_type: 0 });
    }

    fn assert_can_escape_for_type(escape_type: felt) {
        let current_escape = escape::read();
        // TODO Hopefuly there will be a way to directly get the block timestamp without having to do this magic (will do a PR in their repo RN) 
        let block_timestamp = unbox(get_block_info()).block_timestamp;

        assert(current_escape.active_at != 0_u64, 'argent/not-escaping');
        assert(current_escape.active_at <= block_timestamp, 'argent/inactive-escape');
        assert(current_escape.escape_type == escape_type, 'argent/invalid-escape-type');
    }

    #[inline(always)]
    fn assert_valid_guardian_backup(new_guardian: felt) {
        if new_guardian.is_zero() {
            assert(guardian_backup::read().is_zero(), 'argent/guardian-backup-required');
        }
    }

    #[inline(always)]
    fn assert_guardian_set() {
        assert(guardian::read() != 0, 'argent/guardian-required');
    }

    #[inline(always)]
    fn assert_can_escape_signer() {
        let current_escape = escape::read();
        if current_escape.active_at != 0_u64 {
            assert(
                current_escape.escape_type == ESCAPE_TYPE_SIGNER, 'argent/cannot-override-escape'
            );
        }
    }
}
