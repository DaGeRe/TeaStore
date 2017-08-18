/**
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package tools.descartes.petstore.image.cache;

import java.util.Random;
import java.util.function.Predicate;

import tools.descartes.petstore.image.cache.entry.ICachable;
import tools.descartes.petstore.image.storage.IDataStorage;

public class RandomReplacement<T extends ICachable<T>> extends AbstractQueueCache<T> {

	private Random rand = new Random();
	
	public RandomReplacement() {
		super();
	}
	
	public RandomReplacement(long maxCacheSize) {
		super(maxCacheSize);
	}
	
	public RandomReplacement(long maxCacheSize, Predicate<T> cachingRule) {
		super(maxCacheSize, cachingRule);
	}
	
	public RandomReplacement(IDataStorage<T> cachedStorage, long maxCacheSize, Predicate<T> cachingRule) {
		super(cachedStorage, maxCacheSize, cachingRule);
	}
	
	public RandomReplacement(IDataStorage<T> cachedStorage, long maxCacheSize, Predicate<T> cachingRule, long seed) {
		super(cachedStorage, maxCacheSize, cachingRule);
		setSeed(seed);
	}
	
	public void setSeed(long seed) {
		rand.setSeed(seed);
	}

	@Override
	protected void removeEntryByCachingStrategy() {
		entries.remove(rand.nextInt(entries.size()));
	}

}