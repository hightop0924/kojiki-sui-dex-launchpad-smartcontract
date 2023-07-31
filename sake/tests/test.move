#[test_only]
module sake::tests {
  use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
  use sui::test_utils::{assert_eq};
  use sui::coin::{burn_for_testing as burn};

  use sake::sake::{Self, SakeStorage, SakeAdminCap};
  use library::test_utils::{people, scenario};
  use library::foo::{Self, FooStorage};


  #[test]
  #[expected_failure(abort_code = sake::sake::ERROR_NOT_ALLOWED_TO_MINT)]
  fun test_mint_amount_error() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_ipx(test);

      next_tx(test, alice);
      {
        let ipx_storage = test::take_shared<SakeStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);

        burn(sake::mint(&mut ipx_storage, publisher, 1, ctx(test)));

        assert_eq(sake::is_minter(&ipx_storage, id), true);

        test::return_shared(ipx_storage);
        test::return_shared(foo_storage);
      };
      test::end(scenario);
  }

  #[test]
  fun test_mint() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_ipx(test);

      next_tx(test, alice);
      {
        let ipx_storage = test::take_shared<SakeStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<SakeAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        sake::add_minter(&admin_cap, &mut ipx_storage, id);
        assert_eq(burn(sake::mint(&mut ipx_storage, publisher, 100, ctx(test))), 100);


        test::return_shared(ipx_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }
  
  #[test]
  #[expected_failure(abort_code = sake::sake::ERROR_NOT_ALLOWED_TO_MINT)]
  fun test_remove_minter() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_ipx(test);

      next_tx(test, alice);
      {
        let ipx_storage = test::take_shared<SakeStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<SakeAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        sake::add_minter(&admin_cap, &mut ipx_storage, id);
        assert_eq(burn(sake::mint(&mut ipx_storage, publisher, 100, ctx(test))), 100);

        sake::remove_minter(&admin_cap, &mut ipx_storage, id);

        assert_eq(sake::is_minter(&ipx_storage, id), false);
        assert_eq(burn(sake::mint(&mut ipx_storage, publisher, 100, ctx(test))), 100);

        test::return_shared(ipx_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  #[test]
  fun test_burn() {
      let scenario = scenario();
      let (alice, _) = people();
      let test = &mut scenario;

      start_ipx(test);

      next_tx(test, alice);
      {
        let ipx_storage = test::take_shared<SakeStorage>(test);
        let foo_storage = test::take_shared<FooStorage>(test);
        let admin_cap = test::take_from_address<SakeAdminCap>(test, alice);

        let publisher = foo::get_publisher(&foo_storage);
        let id = foo::get_publisher_id(&foo_storage);


        sake::add_minter(&admin_cap, &mut ipx_storage, id);

        let coin_ipx = sake::mint(&mut ipx_storage, publisher, 100, ctx(test));
        assert_eq(sake::burn(&mut ipx_storage, coin_ipx), 100);


        test::return_shared(ipx_storage);
        test::return_shared(foo_storage);
        test::return_to_address(alice, admin_cap);
      };
      test::end(scenario);
  }

  fun start_ipx(test: &mut Scenario) {
       let (alice, _) = people();
       next_tx(test, alice);
       {
        sake::init_for_testing(ctx(test));
        foo::init_for_testing(ctx(test));
       };
  }
}