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
    
    // Verify provider status
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
    
    // First verify the provider
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
        types.uint(1000000), // 1 STX
        types.uint(10)
      ], provider.address)
    ]);
    
    block.receipts[0].result.expectOk().expectUint(0);
    
    // Verify experience details
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
  name: "Ensure users can book experiences",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const provider = accounts.get('wallet_1')!;
    const user = accounts.get('wallet_2')!;
    
    // Setup: Verify provider and create experience
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
    
    let block = chain.mineBlock([
      Tx.contractCall('itinerary_planner', 'book-experience', [
        types.uint(0)
      ], user.address)
    ]);
    
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify booking details
    let query = chain.callReadOnlyFn(
      'itinerary_planner',
      'get-booking',
      [types.uint(0), types.principal(user.address)],
      deployer.address
    );
    
    assertEquals(query.result.expectSome().data.status, "booked");
  }
});