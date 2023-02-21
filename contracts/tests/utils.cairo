use starknet_testing::set_block_timestamp;
use contracts::ArgentAccount;
use starknet_testing::set_caller_address;
use starknet::contract_address_const;

// Probably there is a better way to structure and import all this ... 

const DEFAULT_TIMESTAMP: u64 = 42_u64;
const ESCAPE_SECURITY_PERIOD: felt = 604800; // 7 * 24 * 60 * 60;  // 7 days
const ESCAPE_TYPE_GUARDIAN: felt = 1;
const ESCAPE_TYPE_SIGNER: felt = 2;

const signer_pubkey: felt = 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca;
const signer_r: felt = 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69;
const signer_s: felt = 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77;

const guardian_pubkey: felt = 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5;
const guardian_r: felt = 0x1734f5510c8b862984461d2221411d12a706140bae629feac0aad35f4d91a19;
const guardian_s: felt = 0x75c904c1969e5b2bf2e9fedb32d6180f06288d81a6a2164d876ea4be2ae7520;

const guardian_backup_pubkey: felt =
    0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20;
const guardian_backup_r: felt = 0x1e03a158a4142532f903caa32697a74fcf5c05b762bb866cec28670d0a53f9a;
const guardian_backup_s: felt = 0x74be76fe620a42899bc34afce7b31a058408b23c250805054fca4de4e0121ca;


fn set_block_timestamp_to_default() {
    set_block_timestamp(DEFAULT_TIMESTAMP);
}


fn initialize_account() {
    ArgentAccount::initialize(signer_pubkey, guardian_pubkey, 0);
}

fn initialize_account_without_guardian() {
    ArgentAccount::initialize(signer_pubkey, 0, 0);
}

fn set_caller_to_pseudo_random() {
    set_caller_address(contract_address_const::<42>());
}
