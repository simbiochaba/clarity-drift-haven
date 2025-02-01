import {
  Clarinet,
  Tx,
  Chain,
  Account,
  types
} from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
  name: "Ensure that providers can be verified by contract owner",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const provider = accounts.get('wallet_1')!;

    let block = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'verify-provider', [
        types.principal(provider.address)
      ], deployer.address)
    ]);
    
    block.receipts[0].result.expectOk().expectBool(true);
    
    let query = chain.callReadOnlyFn(
      'itinerary_planner',
      'is-verified',
      [types.principal(provider.address)],
      deployer.address
    );
    
    assertEquals(query.result, types.bool(true));
  }
});

Clarinet.test({
  name: "Ensure that verified providers can create experiences",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const provider = accounts.get('wallet_1')!;
    
    chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'verify-provider', [
        types.principal(provider.address)
      ], deployer.address)
    ]);
    
    let block = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'create-experience', [
        types.utf8("Mountain Trek"),
        types.utf8("Amazing mountain trekking experience"),
        types.utf8("Nepal"),
        types.uint(1000000),
        types.uint(10)
      ], provider.address)
    ]);
    
    block.receipts[0].result.expectOk().expectUint(0);
    
    let query = chain.callReadOnlyFn(
      'itinerary_planner',
      'get-experience',
      [types.uint(0)],
      deployer.address
    );
    
    assertEquals(query.result.expectSome().data.title, "Mountain Trek");
  }
});

Clarinet.test({
  name: "Ensure users can book and review experiences",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const provider = accounts.get('wallet_1')!;
    const user = accounts.get('wallet_2')!;
    
    chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'verify-provider', [
        types.principal(provider.address)
      ], deployer.address),
      Tx.contractCall('itinerary_planner', 'create-experience', [
        types.utf8("Mountain Trek"),
        types.utf8("Amazing mountain trekking experience"),
        types.utf8("Nepal"),
        types.uint(1000000),
        types.uint(10)
      ], provider.address)
    ]);
    
    let bookBlock = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'book-experience', [
        types.uint(0)
      ], user.address)
    ]);
    
    bookBlock.receipts[0].result.expectOk().expectBool(true);
    
    let reviewBlock = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'submit-review', [
        types.uint(0),
        types.uint(5),
        types.utf8("Excellent experience!")
      ], user.address)
    ]);
    
    reviewBlock.receipts[0].result.expectOk().expectBool(true);
    
    let reviewQuery = chain.callReadOnlyFn(
      'itinerary_planner',
      'get-review',
      [types.uint(0), types.principal(user.address)],
      deployer.address
    );
    
    assertEquals(reviewQuery.result.expectSome().data.rating, types.uint(5));
    
    let providerQuery = chain.callReadOnlyFn(
      'itinerary_planner',
      'get-provider-stats',
      [types.principal(provider.address)],
      deployer.address
    );
    
    assertEquals(providerQuery.result.expectSome().data["total-reviews"], types.uint(1));
  }
});
