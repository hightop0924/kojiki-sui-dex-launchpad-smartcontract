module launchpad::project_entries {
    use launchpad::project::{AdminCap, ProjectBank};
    use sui::tx_context::TxContext;
    use sui::coin::{Coin};
    use launchpad::project;
    use std::vector;
    use sui::clock::Clock;
    use launchpad::kyc::Kyc;
    use launchpad::version::Version;

    public entry fun change_admin(adminCap: AdminCap,
                                  to: address,
                                  version: &mut Version) {
        project::change_admin(adminCap, to, version);
    }

    public entry fun create_project<COIN, TOKEN>(adminCap: &AdminCap,
                                                 projectBank: &mut ProjectBank,
                                                 owner: address,
                                                 vesting_type: u8,
                                                 cliff_time: u64,
                                                 tge_ms: u64,
                                                 unlock_percent: u64,
                                                 linear_time_ms: u64,
                                                 coin_decimals: u8,
                                                 token_decimals: u8,
                                                 require_kyc: bool,
                                                 version: &mut Version,
                                                 clock: &Clock,
                                                 ctx: &mut TxContext) {
        project::create_project<COIN, TOKEN>(
            adminCap,
            projectBank,
            owner,
            vesting_type,
            cliff_time,
            tge_ms,
            unlock_percent,
            linear_time_ms,
            coin_decimals,
            token_decimals,
            require_kyc,
            version,
            clock,
            ctx
        );
    }

    public entry fun change_owner<COIN, TOKEN>(
        new_owner: address,
        projectBank: &mut ProjectBank,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        project::change_owner<COIN, TOKEN>(new_owner, projectBank, version, ctx);
    }

    public entry fun add_milestone<COIN, TOKEN>(_adminCap: &AdminCap,
                                                projectBank: &mut ProjectBank,
                                                time: u64,
                                                percent: u64,
                                                clock: &Clock,
                                                version: &mut Version,
                                                ctx: &mut TxContext) {
        project::add_milestone<COIN, TOKEN>(_adminCap, projectBank, time, percent, clock, version, ctx);
    }

    public entry fun reset_milestone<COIN, TOKEN>(_adminCap: &AdminCap,
                                                  projectBank: &mut ProjectBank,
                                                  version: &mut Version,
                                                  ctx: &mut TxContext) {
        project::reset_milestone<COIN, TOKEN>(_adminCap, projectBank, version, ctx);
    }

    public entry fun setup_project<COIN, TOKEN>(_adminCap: &AdminCap,
                                                projectBank: &mut ProjectBank,
                                                round: u8,
                                                usewhitelist: bool,
                                                swap_ratio_sui: u64,
                                                swap_ratio_token: u64,
                                                max_allocate: u64,
                                                start_time: u64,
                                                end_time: u64,
                                                soft_cap: u64,
                                                hard_cap: u64,
                                                clock: &Clock,
                                                version: &mut Version,
                                                _ctx: &mut TxContext) {
        project::setup_project<COIN, TOKEN>(
            _adminCap,
            projectBank,
            round,
            usewhitelist,
            swap_ratio_sui,
            swap_ratio_token,
            max_allocate,
            start_time,
            end_time,
            soft_cap,
            hard_cap,
            clock,
            version,
            _ctx
        );
    }

    public entry fun add_max_allocate<COIN, TOKEN>(admin_cap: &AdminCap,
                                                   users: vector<address>,
                                                   max_allocates: vector<u64>,
                                                   projectBank: &mut ProjectBank,
                                                   version: &mut Version,
                                                   ctx: &mut TxContext) {
        project::add_max_allocations<COIN, TOKEN>(admin_cap, users, max_allocates, projectBank, version, ctx);
    }

    public entry fun set_project_public<COIN, TOKEN>(
        _adminCap: &AdminCap,
        projectBank: &mut ProjectBank,
        round: u8,
        _clock: &Clock,
        _version: &mut Version,
        _ctx: &mut TxContext
    ) {
        project::set_project_public<COIN, TOKEN>(
            _adminCap,
            projectBank,
            round,
            _clock,
            _version,
            _ctx
        );
    }

    public entry fun remove_max_allocate<COIN, TOKEN>(_admin_cap: &AdminCap,
                                                      users: vector<address>,
                                                      projectBank: &mut ProjectBank,
                                                      version: &mut Version,
                                                      ctx: &mut TxContext) {
        project::clear_max_allocate<COIN, TOKEN>(_admin_cap, users, projectBank, version, ctx);
    }

    public entry fun add_whitelist<COIN, TOKEN>(_adminCap: &AdminCap,
                                                projectBank: &mut ProjectBank,
                                                user_list: vector<address>,
                                                version: &mut Version,
                                                ctx: &mut TxContext) {
        project::add_whitelist<COIN, TOKEN>(_adminCap, projectBank, user_list, version, ctx);
    }

    public entry fun remove_whitelist<COIN, TOKEN>(_adminCap: &AdminCap,
                                                   projectBank: &mut ProjectBank,
                                                   user_list: vector<address>,
                                                   version: &mut Version,
                                                   ctx: &mut TxContext) {
        project::remove_whitelist<COIN, TOKEN>(_adminCap, projectBank, user_list, version, ctx);
    }

    public entry fun start_fund_raising<COIN, TOKEN>(
        _adminCap: &AdminCap,
        projectBank: &mut ProjectBank,
        clock: &Clock,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        project::start_fund_raising<COIN, TOKEN>(_adminCap, projectBank, clock, version, ctx);
    }

    public entry fun buy<COIN, TOKEN>(
        coin: Coin<COIN>,
        amount: u64,
        projectBank: &mut ProjectBank,
        clock: &Clock,
        kyc: &Kyc,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        let coins = vector::empty<Coin<COIN>>();
        vector::push_back(&mut coins, coin);
        project::buy<COIN, TOKEN>(coins, amount, projectBank, clock, kyc, version, ctx);
    }

    public entry fun end_fund_raising<COIN, TOKEN>(
        _adminCap: &AdminCap,
        projectBank: &mut ProjectBank,
        clock: &Clock,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        project::end_fund_raising<COIN, TOKEN>(_adminCap, projectBank, clock, version, ctx);
    }

    public entry fun distribute_raised_fund<COIN, TOKEN>(
        projectBank: &mut ProjectBank,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        project::distribute_raised_fund<COIN, TOKEN>(projectBank, version, ctx);
    }

    public entry fun refund_token_to_owner<COIN, TOKEN>(
        projectBank: &mut ProjectBank,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        project::refund_token_to_owner<COIN, TOKEN>(projectBank, version, ctx);
    }

    public entry fun deposit_token<COIN, TOKEN>(
        token: Coin<TOKEN>,
        value: u64,
        projectBank: &mut ProjectBank,
        version: &mut Version,
        ctx: &mut TxContext
    ) {
        let tokens = vector::empty<Coin<TOKEN>>();
        vector::push_back(&mut tokens, token);
        project::deposit_token<COIN, TOKEN>(tokens, value, projectBank, version, ctx);
    }

    public entry fun claim_token<COIN, TOKEN>(projectBank: &mut ProjectBank,
                                              clock: &Clock,
                                              version: &mut Version,
                                              ctx: &mut TxContext) {
        project::claim_token<COIN, TOKEN>(projectBank, clock, version, ctx);
    }

    public entry fun claim_refund<COIN, TOKEN>(projectBank: &mut ProjectBank,
                                               version: &mut Version,
                                               ctx: &mut TxContext) {
        project::claim_refund<COIN, TOKEN>(projectBank, version, ctx);
    }

    public entry fun vote<COIN, TOKEN>(projectBank: &mut ProjectBank,
                                       version: &mut Version,
                                       ctx: &mut TxContext) {
        project::vote<COIN, TOKEN>(projectBank, version, ctx);
    }
}
