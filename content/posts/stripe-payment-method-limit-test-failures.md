---
title: 'Fixing failing tests caused by Stripe Payment Method Limits'
date: 2019-12-19T18:16:38-05:00
draft: false
description: How I fixed the tests that started failing due to too many payment methods attached to customers
categories:
  - elixir
featured_image:
tags:
  - programming
  - stripe
author: 'Lloyd Ramey'
---

# The problem

## Some Context

I've been using Stripe to handle payments for Schedule Guru; and some of my
tests call out to stripe. So far the main issue this has caused is that they
run fairly slowly. I have around 50 tests that call out to stripe, and when I
run them they increase my test run time from ~20 seconds to ~60 seconds. This
isn't that bad from an absolute time to run all of my tests; and the added
benefit of being able to test my payment handling logic is worth it.

## CI/CD via Github

I currently use github actions to run my tests on any merge to master, and if
they pass automatically deploy. This means that these tests are usually run
a few times most evenings; which is exactly what I intended. What I didn't
realize is that some of the stripe tests attach test payment methods to the
customers I create for testing; and that they don't clean up after themselves
when they create these methods.

## What happened

This week that bit me. My tests started failing with a 400 from stripe's API
indicated that I had reached the maximum number of payment methods on a customer.

That was news to me; as I didn't think the tests were actually attaching these
payment methods. However, until I fixed this the tests would fail to run and I
couldn't use github to run my tests and deploy.

# The Solution

This isn't a very complicated issue - the root cause is that my tests aren't cleaning
up after themselves. So the solution was to learn how ExUnit handles cleanup logic.
I also wanted a quick and dirty solution so that my tests would be able to run again.

After some fairly quick googling, I found that ExUnit supports `on_exit` callbacks.
They can be registered on demand, and will always run regardless of errors in tests
or other callbacks.

## Paging

So now I new how to run the code, I needed to write the code. I'm using stripity_stripe
to communicate with stripe; which doesn't have a built in paging mechanism (it's a fairly
low level library). However it does expose a nice and consistent api for maching
requests to Stripe.

Stripe supports at least a few hundred payment methods attached to a customer at a time,
however their API limits pages to at most 100 objects. So I needed to write some code to
execute an action for each object.

My first attempt focused on just paging through the customers:

```elixir
def for_each(stripe_account, starting_after \\ nil, action) do
  params = if starting_after != nil,
    do: %{limit: 100, start_after: starting_after},
    else: %{limit: 100}

  case Stripe.Customer.list(params, connect_account: stripe_account) do
    {:ok %{data: data, has_more: has_more}} ->
      Enum.each(data, action)

      if has_more,
        do: for_each(stripe_account, List.last(data).id, action)

    other -> raise other
  end
end
```

This allowed me to list all of my customer in my test account, and got me on the right path.
I was then able to modify this to support additional object types like so:

```elixir
def for_each(module, stripe_account, params \\ %{}, action) do
  case module.list(params, connect_account: stripe_account) do
    {:ok %{data: data, has_more: has_more}} ->
      Enum.each(data, action)

      if has_more,
        do: for_each(
          stripe_account,
          Map.put(params, :start_after, List.last(data).id),
          action
        )

    other -> raise other
  end
end
```

## The Simple fix

In order to get my tests passing, I was able to use this in iex to detach the payment
methods from the test customers:

```elixir
for_each(Stripe.Customer, stripe_account, fn customer ->
  for_each(Stripe.PaymentMethod, stripe_account, %{customer: customer.id}, fn method ->
    Stripe.PaymentMethod.detach(method.id, connect-account: stripe_account)
  end)
end)
```

This fixed the issue of my tests failing; however it didn't actually address the
root cause. To address that, I had to create an on_exit callback that would detach
any payment methods attached during a test.

I already tag all of the tests which communicate with stripe so that I can exclude
them when running the tests locally; and I don't want this exit handler called when
those tests are aren't even run. The simplest solution is to run that code after any
test which interacts with stripe. I ended up going with this solution for the time
being despite a few issues. The most significant issue with this approach is that
it detaches all payment methods from all customers, regardless of if they were
attached during this test run or not. I'll be updating this to be more selective
down the road; however the simplicity is worth it for the time being.

I created an ExUnit case template to handle adding the callbacks:

```elixir
defmodule StripeCase do
  @moduledoc """
  This template handles cleaning up after stripe based tests
  """
  use ExUnit.CaseTemplate

  setup_all %{tenant: tenant} do
    config = ExUnit.configuration()

    exclude = Keyword.get(config, :exclude, [])

    if not Enum.member?(exclude, :stripe) do
      stripe_account = "act_1234" # get stripe connect acccount

      on_exit(fn ->
        for_each(Stripe.Customer, stripe_account, fn customer ->
          for_each(
            Stripe.PaymentMethod,
            stripe_account,
            %{customer: customer, type: "card"},
            fn method ->
              IO.puts(:stderr, "Cleaning up stripe payment method #{method.id}")

              Stripe.PaymentMethod.detach(%{payment_method: method.id},
                connect_account: stripe_account
              )
            end
          )
        end)
      end)
    end

    :ok
  end

  defp for_each(module, account_id, params \\ %{}, body) do
    with {:ok, %{data: data, has_more: has_more}} <-
           module.list(params, connect_account: account_id) do
      Enum.each(data, body)

      if has_more,
        do:
          for_each(
            module,
            account_id,
            Map.put(params, :starting_after, List.last(data).id),
            body
          )
    else
      err -> raise err
    end
  end
end
```
