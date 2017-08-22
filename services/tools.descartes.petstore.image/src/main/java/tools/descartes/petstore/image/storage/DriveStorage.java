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
package tools.descartes.petstore.image.storage;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.function.Predicate;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import tools.descartes.petstore.entities.ImageSize;
import tools.descartes.petstore.image.ImageDB;
import tools.descartes.petstore.image.StoreImage;

public class DriveStorage implements IDataStorage<StoreImage> {

	protected Path workingDir;
	private ImageDB imgDB;
	private Predicate<StoreImage> storageRule;
	private Logger log = LoggerFactory.getLogger(DriveStorage.class);
	
	public DriveStorage(Path workingDir, ImageDB imgDB, Predicate<StoreImage> storageRule) {
		if (workingDir == null) {
			log.error("The supplied working directory is null.");
			throw new NullPointerException("The supplied working directory is null.");
		}
		if (imgDB == null) {
			log.error("The supplied image database is null.");
			throw new NullPointerException("The supplied image database is null.");
		}
		if (storageRule == null) {
			log.error("The supplied rule to determine if an image can be stored is null.");
			throw new NullPointerException("The supplied rule to determine if an image can be stored is null.");
		}
		
		this.workingDir = workingDir.normalize();
		this.imgDB = imgDB;
		this.storageRule = storageRule;
	}
	
	@Override
	public boolean dataExists(long id) {
		return workingDir.resolve(Long.toString(id)).toFile().exists();
	}

	protected StoreImage loadFromDisk(Path imgFile, long id) {
		byte[] imgData = null;
		try {
			imgData = Files.readAllBytes(imgFile);
		} catch (IOException ioException) {
			log.warn("An IOException occured while trying to read the file \"" + imgFile.toAbsolutePath()
					+ "\" from disk. Returning null.", ioException);
			return null;
		}
		
		if (imgData == null) {
			return null;
		}
		
		ImageSize size = imgDB.getImageSize(id);
		if (size == null) {
			return null;
		}
		
		return new StoreImage(id, imgData, size);
	}
	
	@Override
	public StoreImage loadData(long id) {
		Path imgFile = workingDir.resolve(Long.toString(id));
		if (!imgFile.toFile().exists()) {
			return null;
		}
		
		return loadFromDisk(imgFile, id);
	}

	@Override
	public boolean saveData(StoreImage data) {
		// We return true so we do not trigger an error. This is intended
		if (!dataIsStorable(data)) {
			return true;
		}
		
		Path imgFile = workingDir.resolve(Long.toString(data.getId()));
		if (imgFile.toFile().exists()) {
			return true;
		}
		
		try {
			Files.write(imgFile, data.getByteArray(), 
					StandardOpenOption.CREATE, StandardOpenOption.WRITE, StandardOpenOption.TRUNCATE_EXISTING);
		} catch (IOException ioException) {
			log.warn("An IOException occured while trying to write the file \"" + imgFile.toAbsolutePath() 
					+ "\" to disk.", ioException);
			return false;
		}
		
		return true;
	}

	@Override
	public boolean dataIsStorable(StoreImage data) {
		return storageRule.test(data);
	}

	@Override
	public boolean deleteData(StoreImage data) {
		Path imgFile = workingDir.resolve(Long.toString(data.getId()));
		if (imgFile.toFile().exists()) {
			return true;
		}
		
		return imgFile.toFile().delete();
	}

}
