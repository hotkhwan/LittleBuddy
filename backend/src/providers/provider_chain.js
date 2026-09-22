/** Calls providers in order. Local fallback belongs last in the chain. */
export function createProviderChain(providers) {
  const chain = providers.filter(Boolean);
  if (!chain.length) throw new TypeError('provider chain must not be empty');
  return {
    name: chain.map((provider) => provider.name).join(' -> '),
    async generateTurn(input) {
      const failures = [];
      for (const provider of chain) {
        try {
          const result = await provider.generateTurn(input);
          return { ...result, selectedProvider: provider.name, providerFailures: failures };
        } catch (error) {
          if (input.signal?.aborted) throw error;
          failures.push({ provider: provider.name, reason: String(error?.message || 'provider error') });
        }
      }
      throw new AggregateError(failures, 'all tutor providers failed');
    },
  };
}
